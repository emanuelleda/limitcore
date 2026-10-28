package dev.limitcore;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.HexFormat;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.http.CacheControl;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/limits")
public class RateLimitController {
    private static final String SLIDING_WINDOW_ALGORITHM = "sliding-window";
    private static final String IDENTIFIER_SCOPE = "identifier";
    private static final DefaultRedisScript<Long> FIXED_WINDOW = new DefaultRedisScript<>("""
        local now = redis.call('TIME')
        local ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
        redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', ms)
        local count = redis.call('GET', KEYS[1])
        if not count then
          if redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[3]) then return 0 end
          redis.call('SET', KEYS[1], 1, 'PX', ARGV[1])
          redis.call('ZADD', KEYS[2], ms + tonumber(ARGV[1]), KEYS[1])
          redis.call('PEXPIRE', KEYS[2], tonumber(ARGV[1]) * 2)
          return 1
        end
        if tonumber(count) >= tonumber(ARGV[2]) then return 0 end
        redis.call('INCR', KEYS[1])
        return 1
        """, Long.class);
    private static final DefaultRedisScript<Long> TOKEN_BUCKET = new DefaultRedisScript<>("""
        local now = redis.call('TIME')
        local ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
        redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', ms)
        if not redis.call('ZSCORE', KEYS[2], KEYS[1]) and
            redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[4]) then return 0 end
        local state = redis.call('HMGET', KEYS[1], 'tokens', 'updated')
        local tokens = tonumber(state[1]) or tonumber(ARGV[1])
        local updated = tonumber(state[2]) or ms
        local elapsed = math.max(0, ms - updated)
        tokens = math.min(tonumber(ARGV[1]), tokens + elapsed * tonumber(ARGV[2]) / 1000)
        local allowed = 0
        if tokens >= 1 then tokens = tokens - 1; allowed = 1 end
        redis.call('HSET', KEYS[1], 'tokens', tokens, 'updated', ms)
        redis.call('PEXPIRE', KEYS[1], ARGV[3])
        redis.call('ZADD', KEYS[2], ms + tonumber(ARGV[3]), KEYS[1])
        redis.call('PEXPIRE', KEYS[2], tonumber(ARGV[3]) * 2)
        return allowed
        """, Long.class);
    private static final DefaultRedisScript<Long> SLIDING_WINDOW = new DefaultRedisScript<>("""
        local now = redis.call('TIME')
        local ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
        redis.call('ZREMRANGEBYSCORE', KEYS[3], '-inf', ms)
        if not redis.call('ZSCORE', KEYS[3], KEYS[1]) and
            redis.call('ZCARD', KEYS[3]) >= tonumber(ARGV[3]) then return 0 end
        redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ms - tonumber(ARGV[1]))
        if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) then return 0 end
        local seq = redis.call('INCR', KEYS[2])
        redis.call('PEXPIRE', KEYS[2], ARGV[1])
        redis.call('ZADD', KEYS[1], ms, tostring(ms) .. ':' .. tostring(seq))
        redis.call('PEXPIRE', KEYS[1], ARGV[1])
        redis.call('ZADD', KEYS[3], ms + tonumber(ARGV[1]), KEYS[1])
        redis.call('PEXPIRE', KEYS[3], tonumber(ARGV[1]) * 2)
        return 1
        """, Long.class);
    private final StringRedisTemplate redis;
    private final byte[] configuredApiKeyDigest;
    private final Map<String,List<byte[]>> tenantKeyDigests;
    private final AtomicReference<MeterRegistry> meterRegistry = new AtomicReference<>();
    private final int capacity;
    private final int maxActiveKeys;
    private final Map<String,Integer> tenantCapacities;
    private final int windowSeconds;
    private final String algorithm;
    private final String keyScope;

    @org.springframework.beans.factory.annotation.Autowired
    public RateLimitController(StringRedisTemplate redis,
            @Value("${limitcore.api-key:}") String apiKey,
            @Value("${limitcore.capacity:100}") int capacity,
            @Value("${limitcore.window-seconds:60}") int windowSeconds,
            @Value("${limitcore.algorithm:fixed-window}") String algorithm,
            @Value("${limitcore.tenants:}") String tenants,
            @Value("${limitcore.tenant-capacities:}") String tenantCapacityConfig,
            @Value("${limitcore.max-active-keys:1000}") int maxActiveKeys,
            @Value("${limitcore.key-scope:identifier}") String keyScope) {
        this.redis = redis;
        if (apiKey == null || apiKey.length() > 256)
            throw new IllegalArgumentException("Legacy API credential must not exceed 256 characters");
        Map<String,List<String>> tenantKeys = parseTenants(tenants);
        if (!apiKey.isBlank() && tenantKeys.values().stream().flatMap(List::stream).anyMatch(apiKey::equals))
            throw new IllegalArgumentException("Legacy and tenant credentials must differ");
        this.configuredApiKeyDigest = apiKey.isBlank() ? null : sha256(apiKey.getBytes(StandardCharsets.UTF_8));
        Map<String,List<byte[]>> hashedKeys = new HashMap<>();
        for (var entry : tenantKeys.entrySet()) {
            hashedKeys.put(entry.getKey(), entry.getValue().stream()
                    .map(value -> sha256(value.getBytes(StandardCharsets.UTF_8))).toList());
        }
        this.tenantKeyDigests = Map.copyOf(hashedKeys);
        this.tenantCapacities = parseCapacities(tenantCapacityConfig, tenantKeys);
        if (capacity < 1 || capacity > 1000000 || windowSeconds < 1 || windowSeconds > 86400)
            throw new IllegalArgumentException("Invalid server-side quota configuration");
        if (!List.of("fixed-window", "token-bucket", SLIDING_WINDOW_ALGORITHM).contains(algorithm))
            throw new IllegalArgumentException("Unsupported algorithm");
        if (algorithm.equals(SLIDING_WINDOW_ALGORITHM) && capacity > 10000)
            throw new IllegalArgumentException("Sliding window capacity must not exceed 10000");
        if (maxActiveKeys < 1 || maxActiveKeys > 100000)
            throw new IllegalArgumentException("Invalid maximum active keys configuration");
        if (!List.of(IDENTIFIER_SCOPE, "tenant").contains(keyScope))
            throw new IllegalArgumentException("Unsupported key scope");
        this.keyScope = keyScope;
        this.maxActiveKeys = maxActiveKeys;
        this.capacity = capacity;
        this.windowSeconds = windowSeconds;
        this.algorithm = algorithm;
    }

    public RateLimitController(StringRedisTemplate redis, String apiKey, int capacity,
            int windowSeconds, String algorithm) {
        this(redis, apiKey, capacity, windowSeconds, algorithm, "", "", 1000, IDENTIFIER_SCOPE);
    }

    public RateLimitController(StringRedisTemplate redis, String apiKey, int capacity,
            int windowSeconds, String algorithm, String tenants) {
        this(redis, apiKey, capacity, windowSeconds, algorithm, tenants, "", 1000, IDENTIFIER_SCOPE);
    }

    public RateLimitController(StringRedisTemplate redis, String apiKey, int capacity,
            int windowSeconds, String algorithm, String tenants, String tenantCapacities) {
        this(redis, apiKey, capacity, windowSeconds, algorithm, tenants, tenantCapacities, 1000, IDENTIFIER_SCOPE);
    }

    private static Map<String,List<String>> parseTenants(String configuration) {
        Map<String,List<String>> parsed = new HashMap<>();
        Set<String> credentials = new HashSet<>();
        if (configuration == null || configuration.isBlank()) return Map.of();
        for (String entry : configuration.split(",")) {
            String[] parts = entry.split("=", 2);
            if (parts.length != 2 || !parts[0].matches("[A-Za-z0-9_-]{1,64}")
                    || parsed.containsKey(parts[0]))
                throw new IllegalArgumentException("Invalid tenant credentials configuration");
            List<String> secrets = validateTenantSecrets(parts[1], credentials);
            parsed.put(parts[0], secrets);
            if (parsed.size() > 1000) throw new IllegalArgumentException("Too many tenants");
        }
        return Map.copyOf(parsed);
    }

    private static List<String> validateTenantSecrets(String raw, Set<String> seen) {
        String[] secrets = raw.split("\\|", -1);
        if (secrets.length > 2) throw new IllegalArgumentException("At most two credentials per tenant");
        for (String secret : secrets) {
            if (secret.length() < 16 || secret.length() > 256 || !seen.add(secret))
                throw new IllegalArgumentException("Invalid or duplicate tenant credential");
        }
        return List.of(secrets);
    }

    private static Map<String,Integer> parseCapacities(String configuration, Map<String,List<String>> tenants) {
        Map<String,Integer> capacities = new HashMap<>();
        if (configuration == null || configuration.isBlank()) return Map.of();
        for (String entry : configuration.split(",")) {
            String[] parts = entry.split("=", 2);
            if (parts.length != 2 || !tenants.containsKey(parts[0]))
                throw new IllegalArgumentException("Unknown tenant in capacity configuration");
            int value;
            try { value = Integer.parseInt(parts[1]); }
            catch (NumberFormatException e) { throw new IllegalArgumentException("Invalid tenant capacity", e); }
            if (value < 1 || value > 10000 || capacities.putIfAbsent(parts[0], value) != null)
                throw new IllegalArgumentException("Invalid or duplicate tenant capacity");
        }
        return Map.copyOf(capacities);
    }

    @Autowired
    public void setMeterRegistry(MeterRegistry meterRegistry) {
        this.meterRegistry.set(meterRegistry);
    }

    private void recordDecision(String outcome) {
        MeterRegistry registry = this.meterRegistry.get();
        if (registry != null) {
            registry.counter("limitcore.decisions", "algorithm", algorithm, "outcome", outcome).increment();
        }
    }

    private String authenticate(String apiKey) {
        if (apiKey == null || apiKey.isBlank() || apiKey.length() > 256) return null;
        byte[] candidate = sha256(apiKey.getBytes(StandardCharsets.UTF_8));
        String tenant = null;
        // Compare precomputed fixed-size SHA-256 digests, without an early return.
        for (var entry : tenantKeyDigests.entrySet()) {
            for (byte[] digest : entry.getValue()) {
                if (MessageDigest.isEqual(candidate, digest)) tenant = entry.getKey();
            }
        }
        if (configuredApiKeyDigest != null &&
                MessageDigest.isEqual(candidate, configuredApiKeyDigest)) tenant = "default";
        return tenant;
    }

    private static byte[] sha256(byte[] input) {
        try { return MessageDigest.getInstance("SHA-256").digest(input); }
        catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }

    public record CheckRequest(@NotBlank @Pattern(regexp="[a-zA-Z0-9:_-]{1,128}") String key) {}
    public record CheckResponse(boolean allowed, String algorithm) {}

    @PostMapping("/check")
    public ResponseEntity<CheckResponse> check(
            @RequestHeader(value="X-API-Key", required=false) String apiKey,
            @Valid @RequestBody CheckRequest request) {
        String tenant = authenticate(apiKey);
        if (tenant == null) {
            recordDecision("unauthorized");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
        }

        int quota = tenantCapacities.getOrDefault(tenant, capacity);
        long windowMillis = windowSeconds * 1000L;
        // All keys for the same tenant share a Redis Cluster hash slot.
        String tenantHash = HexFormat.of().formatHex(sha256(tenant.getBytes(StandardCharsets.UTF_8)));
        String slot = "{" + tenantHash + "}";
        // Production may enforce one shared quota per authenticated tenant. In
        // identifier mode, the caller-provided identifier MUST be trusted by the caller.
        String logicalKey = "tenant".equals(keyScope) ? "__tenant_quota__" : request.key();
        String keyHash = HexFormat.of().formatHex(sha256(logicalKey.getBytes(StandardCharsets.UTF_8)));
        String key = "limitcore:" + slot + ":" + keyHash;
        String registry = "limitcore:" + slot + ":registry";
        Long result = switch (algorithm) {
            case "token-bucket" -> redis.execute(TOKEN_BUCKET, List.of(key, registry),
                String.valueOf(quota), String.valueOf((double) quota / windowSeconds),
                String.valueOf(windowMillis), String.valueOf(maxActiveKeys));
            case SLIDING_WINDOW_ALGORITHM -> redis.execute(SLIDING_WINDOW, List.of(key, key + ":seq", registry),
                String.valueOf(windowMillis), String.valueOf(quota), String.valueOf(maxActiveKeys));
            default -> redis.execute(FIXED_WINDOW, List.of(key, registry),
                String.valueOf(windowMillis), String.valueOf(quota), String.valueOf(maxActiveKeys));
        };
        if (result == null) throw new org.springframework.dao.DataAccessResourceFailureException(
                "Redis returned no quota decision");
        boolean allowed = result == 1L;
        recordDecision(allowed ? "allowed" : "denied");
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new CheckResponse(allowed, algorithm));
    }
}
