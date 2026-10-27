package dev.limitcore;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.HexFormat;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/limits")
public class RateLimitController {
    private static final DefaultRedisScript<Long> FIXED_WINDOW = new DefaultRedisScript<>("""
        local count = redis.call('GET', KEYS[1])
        if not count then
          redis.call('SET', KEYS[1], 1, 'PX', ARGV[1], 'NX')
          return 1
        end
        if tonumber(count) >= tonumber(ARGV[2]) then return 0 end
        redis.call('INCR', KEYS[1])
        return 1
        """, Long.class);
    private static final DefaultRedisScript<Long> TOKEN_BUCKET = new DefaultRedisScript<>("""
        local now = redis.call('TIME')
        local ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
        local state = redis.call('HMGET', KEYS[1], 'tokens', 'updated')
        local tokens = tonumber(state[1]) or tonumber(ARGV[1])
        local updated = tonumber(state[2]) or ms
        local elapsed = math.max(0, ms - updated)
        tokens = math.min(tonumber(ARGV[1]), tokens + elapsed * tonumber(ARGV[2]) / 1000)
        local allowed = 0
        if tokens >= 1 then tokens = tokens - 1; allowed = 1 end
        redis.call('HSET', KEYS[1], 'tokens', tokens, 'updated', ms)
        redis.call('PEXPIRE', KEYS[1], ARGV[3])
        return allowed
        """, Long.class);
    private static final DefaultRedisScript<Long> SLIDING_WINDOW = new DefaultRedisScript<>("""
        local now = redis.call('TIME')
        local ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
        redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ms - tonumber(ARGV[1]))
        if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) then return 0 end
        local seq = redis.call('INCR', KEYS[2])
        redis.call('PEXPIRE', KEYS[2], ARGV[1])
        redis.call('ZADD', KEYS[1], ms, tostring(ms) .. ':' .. tostring(seq))
        redis.call('PEXPIRE', KEYS[1], ARGV[1])
        return 1
        """, Long.class);
    private final StringRedisTemplate redis;
    private final String configuredApiKey;
    private final int capacity;
    private final int windowSeconds;
    private final String algorithm;

    public RateLimitController(StringRedisTemplate redis,
            @Value("${limitcore.api-key:}") String apiKey,
            @Value("${limitcore.capacity:100}") int capacity,
            @Value("${limitcore.window-seconds:60}") int windowSeconds,
            @Value("${limitcore.algorithm:fixed-window}") String algorithm) {
        this.redis = redis;
        this.configuredApiKey = apiKey;
        if (capacity < 1 || capacity > 1000000 || windowSeconds < 1 || windowSeconds > 86400)
            throw new IllegalArgumentException("Invalid server-side quota configuration");
        if (!List.of("fixed-window", "token-bucket", "sliding-window").contains(algorithm))
            throw new IllegalArgumentException("Unsupported algorithm");
        this.capacity = capacity;
        this.windowSeconds = windowSeconds;
        this.algorithm = algorithm;
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
        if (configuredApiKey.isBlank() || apiKey == null ||
                !MessageDigest.isEqual(configuredApiKey.getBytes(StandardCharsets.UTF_8),
                    apiKey.getBytes(StandardCharsets.UTF_8)))
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();

        long windowMillis = windowSeconds * 1000L;
        String key = "limitcore:{" + HexFormat.of().formatHex(sha256(request.key().getBytes(StandardCharsets.UTF_8))) + "}";
        Long result = switch (algorithm) {
            case "token-bucket" -> redis.execute(TOKEN_BUCKET, List.of(key),
                String.valueOf(capacity), String.valueOf((double) capacity / windowSeconds),
                String.valueOf(windowMillis));
            case "sliding-window" -> redis.execute(SLIDING_WINDOW, List.of(key, key + ":seq"),
                String.valueOf(windowMillis), String.valueOf(capacity));
            default -> redis.execute(FIXED_WINDOW, List.of(key),
                String.valueOf(windowMillis), String.valueOf(capacity));
        };
        if (result == null) throw new IllegalStateException("Redis returned no result");
        return ResponseEntity.ok(new CheckResponse(result == 1L, algorithm));
    }
}
