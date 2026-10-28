package dev.limitcore;

import org.junit.jupiter.api.Test;
import org.springframework.data.redis.RedisConnectionFailureException;
import static org.junit.jupiter.api.Assertions.*;

class RedisFailureHandlerTest {
    @Test void rejectsOnRedisFailureWithoutLeakingStackTrace() {
        var handler = new RedisFailureHandler();
        var response = handler.handleRedisError(
            new RedisConnectionFailureException("sensitive internal redis hostname"));
        assertEquals(503, response.getStatusCode().value());
        assertEquals(503, response.getBody().getStatus());
        assertFalse(response.getBody().getDetail().contains("hostname"));
        assertTrue(response.getHeaders().getCacheControl().contains("no-store"));
    }
}
