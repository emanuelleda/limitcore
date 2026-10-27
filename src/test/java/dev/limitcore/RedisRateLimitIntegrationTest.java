package dev.limitcore;

import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.DockerImageName;
import static org.junit.jupiter.api.Assertions.*;

class RedisRateLimitIntegrationTest {
    @Test void fixedWindowIsAtomicAcrossConcurrentCallers() throws Exception {
        try (GenericContainer<?> redis = new GenericContainer<>(DockerImageName.parse("redis:7.4-alpine"))
                .withExposedPorts(6379)) {
            redis.start();
            var factory = new LettuceConnectionFactory(new RedisStandaloneConfiguration(redis.getHost(), redis.getMappedPort(6379)));
            factory.afterPropertiesSet();
            try {
                var template = new StringRedisTemplate(factory);
                var controller = new RateLimitController(template, "test-secret", 20, 60, "fixed-window");
                var pool = Executors.newFixedThreadPool(12);
                try {
                    var start = new CountDownLatch(1);
                    var accepted = new AtomicInteger();
                    var futures = new java.util.ArrayList<Future<?>>();
                    for (int i = 0; i < 100; i++) {
                        futures.add(pool.submit(() -> {
                            start.await();
                            if (controller.check("test-secret", new RateLimitController.CheckRequest("concurrency"))
                                    .getBody().allowed()) accepted.incrementAndGet();
                            return null;
                        }));
                    }
                    start.countDown();
                    for (var future : futures) future.get(30, TimeUnit.SECONDS);
                    assertEquals(20, accepted.get(), "No more than capacity requests may be accepted");
                } finally { pool.shutdownNow(); }
            } finally { factory.destroy(); }
        }
    }

    @Test void tenantCountersRemainIsolatedInRealRedis() {
        try (GenericContainer<?> redis = new GenericContainer<>(DockerImageName.parse("redis:7.4-alpine"))
                .withExposedPorts(6379)) {
            redis.start();
            var factory = new LettuceConnectionFactory(
                new RedisStandaloneConfiguration(redis.getHost(), redis.getMappedPort(6379)));
            factory.afterPropertiesSet();
            try {
                var controller = new RateLimitController(new StringRedisTemplate(factory), "",
                    1, 3600, "fixed-window", "alpha=abcdefghijklmnop,beta=qrstuvwxyzabcdef");
                var request = new RateLimitController.CheckRequest("same-key");
                assertTrue(controller.check("abcdefghijklmnop", request).getBody().allowed());
                assertFalse(controller.check("abcdefghijklmnop", request).getBody().allowed());
                assertTrue(controller.check("qrstuvwxyzabcdef", request).getBody().allowed());
                assertFalse(controller.check("qrstuvwxyzabcdef", request).getBody().allowed());
            } finally { factory.destroy(); }
        }
    }

    @Test void slidingWindowAndTokenBucketRejectAfterCapacity() {
        try (GenericContainer<?> redis = new GenericContainer<>(DockerImageName.parse("redis:7.4-alpine"))
                .withExposedPorts(6379)) {
            redis.start();
            var factory = new LettuceConnectionFactory(new RedisStandaloneConfiguration(redis.getHost(), redis.getMappedPort(6379)));
            factory.afterPropertiesSet();
            try {
                var template = new StringRedisTemplate(factory);
                for (String algorithm : java.util.List.of("sliding-window", "token-bucket")) {
                    var controller = new RateLimitController(template, "test-secret", 3, 3600, algorithm);
                    for (int i = 0; i < 3; i++) {
                        assertTrue(controller.check("test-secret", new RateLimitController.CheckRequest(algorithm))
                                .getBody().allowed());
                    }
                    assertFalse(controller.check("test-secret", new RateLimitController.CheckRequest(algorithm))
                            .getBody().allowed());
                }
            } finally { factory.destroy(); }
        }
    }
}
