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

    @Test void failsClosedWhenRedisIsUnavailable() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class)))
            .thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("Redis unavailable"));
        assertThrows(org.springframework.data.redis.RedisConnectionFailureException.class,
            () -> controller(redis,"fixed-window").check("secret", new RateLimitController.CheckRequest("user-1")));
    }
    @Test void rejectsMissingApiKey() {
        var redis = mock(StringRedisTemplate.class);
        assertEquals(401, controller(redis,"fixed-window")
            .check(null, new RateLimitController.CheckRequest("user-1")).getStatusCode().value());
        verifyNoInteractions(redis);
    }
    @Test void rejectsInvalidQuotaConfiguration() {
        assertThrows(IllegalArgumentException.class, () ->
            new RateLimitController(mock(StringRedisTemplate.class), "secret", 0, 60, "fixed-window"));
    }
    @Test void tenantsHaveIndependentRedisKeys() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(1L);
        var controller = new RateLimitController(redis, "", 10, 60, "fixed-window",
            "alpha=abcdefghijklmnop,beta=qrstuvwxyzabcdef");
        assertTrue(controller.check("abcdefghijklmnop", new RateLimitController.CheckRequest("same")).getBody().allowed());
        assertTrue(controller.check("qrstuvwxyzabcdef", new RateLimitController.CheckRequest("same")).getBody().allowed());
        var captor = org.mockito.ArgumentCaptor.forClass(java.util.List.class);
        verify(redis, times(2)).execute(any(RedisScript.class), captor.capture(), any(String.class), any(String.class));
        assertNotEquals(captor.getAllValues().get(0), captor.getAllValues().get(1));
    }
    @Test void invalidTenantCredentialsFailAtStartup() {
        assertThrows(IllegalArgumentException.class, () ->
            new RateLimitController(mock(StringRedisTemplate.class), "", 10, 60, "fixed-window", "alpha=short"));
    }
    @Test void appliesTenantSpecificCapacities() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(String.class), any(String.class))).thenReturn(1L);
        var controller = new RateLimitController(redis, "", 10, 60, "fixed-window",
            "alpha=abcdefghijklmnop,beta=qrstuvwxyzabcdef", "alpha=2,beta=7");
        controller.check("abcdefghijklmnop", new RateLimitController.CheckRequest("shared"));
        controller.check("qrstuvwxyzabcdef", new RateLimitController.CheckRequest("shared"));
        verify(redis).execute(any(RedisScript.class), anyList(), eq("60000"), eq("2"));
        verify(redis).execute(any(RedisScript.class), anyList(), eq("60000"), eq("7"));
    }
    @Test void rejectsUnknownTenantQuota() {
        assertThrows(IllegalArgumentException.class, () ->
            new RateLimitController(mock(StringRedisTemplate.class), "", 10, 60,
                "fixed-window", "alpha=abcdefghijklmnop", "beta=3"));
    }
    @Test void rejectsInvalidAlgorithm() {
        assertThrows(IllegalArgumentException.class, () -> controller(mock(StringRedisTemplate.class),"unknown"));
    }
}