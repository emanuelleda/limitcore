package dev.limitcore;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.http.ResponseEntity;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
class RateLimitControllerTest {
    @Test void allowsWhenRedisReturnsOne() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(1L);
        var result = new RateLimitController(redis).check(new RateLimitController.CheckRequest("user-1", 10, 60));
        assertTrue(result.getBody().allowed());
    }
    @Test void deniesWhenRedisReturnsZero() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(0L);
        var result = new RateLimitController(redis).check(new RateLimitController.CheckRequest("user-1", 10, 60));
        assertFalse(result.getBody().allowed());
    }
    @Test void failsWhenRedisReturnsNull() {
        var redis = mock(StringRedisTemplate.class);
        assertThrows(IllegalStateException.class, () -> new RateLimitController(redis)
            .check(new RateLimitController.CheckRequest("user-1", 10, 60)));
    }
}