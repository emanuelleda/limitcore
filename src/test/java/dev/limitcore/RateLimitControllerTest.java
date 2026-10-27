package dev.limitcore;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
class RateLimitControllerTest {
    private RateLimitController controller(StringRedisTemplate redis, String algorithm) {
        return new RateLimitController(redis, "secret", 10, 60, algorithm);
    }
    @Test void allows() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(1L);
        assertTrue(controller(redis,"fixed-window").check("secret",new RateLimitController.CheckRequest("user-1")).getBody().allowed());
    }
    @Test void denies() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(0L);
        assertFalse(controller(redis,"fixed-window").check("secret",new RateLimitController.CheckRequest("user-1")).getBody().allowed());
    }
    @Test void rejectsWrongKey() {
        var redis = mock(StringRedisTemplate.class);
        assertEquals(401, controller(redis,"fixed-window").check("wrong",new RateLimitController.CheckRequest("user-1")).getStatusCode().value());
        verifyNoInteractions(redis);
    }
    @Test void acceptsTokenBucket() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class), any(String.class))).thenReturn(1L);
        assertTrue(controller(redis,"token-bucket").check("secret",new RateLimitController.CheckRequest("user-1")).getBody().allowed());
    }
    @Test void acceptsSlidingWindow() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(1L);
        assertTrue(controller(redis,"sliding-window").check("secret",new RateLimitController.CheckRequest("user-1")).getBody().allowed());
    }
    @Test void rejectsOversizedSlidingWindow() {
        assertThrows(IllegalArgumentException.class, () -> new RateLimitController(mock(StringRedisTemplate.class), "secret", 10001, 60, "sliding-window"));
    }
    @Test void rejectsInvalidAlgorithm() {
        assertThrows(IllegalArgumentException.class, () -> controller(mock(StringRedisTemplate.class),"unknown"));
    }
}