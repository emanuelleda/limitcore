package dev.limitcore;

import java.nio.charset.StandardCharsets;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Validates sensitive deployment properties before the application serves
 * traffic. Runtime credentials are never written to logs or error messages.
 */
@Component
@Profile("production")
public final class ProductionConfigurationValidator {
    public ProductionConfigurationValidator(
            @Value("${limitcore.api-key:}") String apiKey,
            @Value("${limitcore.tenants:}") String tenants,
            @Value("${spring.data.redis.ssl.enabled:false}") boolean redisTls,
            @Value("${spring.data.redis.password:}") String redisPassword) {
        validateApiCredentials(apiKey, tenants);
        validateTenantCredentials(tenants);
        validateRedisConnection(redisTls, redisPassword);
    }

    private static void validateApiCredentials(String apiKey, String tenants) {
        if ((apiKey == null || apiKey.isBlank()) && (tenants == null || tenants.isBlank())) {
            throw new IllegalStateException("Production requires configured API credentials");
        }
        if (apiKey != null && !apiKey.isBlank() && apiKey.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("Production API credentials must have at least 32 UTF-8 bytes");
        }
    }

    private static void validateTenantCredentials(String tenants) {
        if (tenants == null || tenants.isBlank()) return;
        for (String tenant : tenants.split(",")) {
            String[] parts = tenant.split("=", 2);
            if (parts.length != 2) throw new IllegalStateException("Invalid tenant configuration");
            for (String credential : parts[1].split("\\|", -1)) {
                if (credential.getBytes(StandardCharsets.UTF_8).length < 32) {
                    throw new IllegalStateException("Production tenant credentials must have at least 32 UTF-8 bytes");
                }
            }
        }
    }

    private static void validateRedisConnection(boolean redisTls, String redisPassword) {
        if (!redisTls) {
            throw new IllegalStateException("Production Redis connections must use TLS");
        }
        if (redisPassword == null || redisPassword.getBytes(StandardCharsets.UTF_8).length < 16) {
            throw new IllegalStateException("Production Redis requires a password of at least 16 UTF-8 bytes");
        }
    }
}
