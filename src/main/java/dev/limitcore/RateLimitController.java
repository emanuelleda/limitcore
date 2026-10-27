package dev.limitcore;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/v1/limits")
public class RateLimitController {
    private static final DefaultRedisScript<Long> SCRIPT = new DefaultRedisScript<>("""
        local current = redis.call('GET', KEYS[1])
        if not current then
          redis.call('SET', KEYS[1], 1, 'PX', ARGV[1], 'NX')
          return 1
        end
        if tonumber(current) >= tonumber(ARGV[2]) then return 0 end
        redis.call('INCR', KEYS[1])
        return 1
        """, Long.class);
    private final StringRedisTemplate redis;
    public RateLimitController(StringRedisTemplate redis) { this.redis = redis; }
    public record CheckRequest(@NotBlank @Pattern(regexp="[a-zA-Z0-9:_-]{1,128}") String key,
                               @Min(1) @Max(1000000) int limit,
                               @Min(1) @Max(86400) int windowSeconds) {}
    public record CheckResponse(boolean allowed, String algorithm) {}
    @PostMapping("/check")
    public ResponseEntity<CheckResponse> check(@Valid @RequestBody CheckRequest request) {
        Long result = redis.execute(SCRIPT, List.of("limitcore:" + request.key()),
                String.valueOf(request.windowSeconds() * 1000L), String.valueOf(request.limit()));
        if (result == null) throw new IllegalStateException("Redis returned no result");
        return ResponseEntity.ok(new CheckResponse(result == 1, "fixed-window"));
    }
}