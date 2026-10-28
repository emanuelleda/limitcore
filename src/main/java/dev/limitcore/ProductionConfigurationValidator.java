package dev.limitcore;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Prevents accidentally exposing a production API without authentication or
 * connecting to Redis over plaintext. Fail fast during Spring context startup.
 */
@Component
@Profile("production")
public final class ProductionConfigurationValidator {
    public ProductionConfigurationValidator(
            @Value("${limitcore.api-key:}") String apiKey,
            @Value("${limitcore.tenants:}") String tenants,
            @Value("${spring.data.redis.ssl.enabled:false}") boolean redisTls) {
        if ((apiKey == null || apiKey.isBlank()) && (tenants == null || tenants.isBlank())) {
            throw new IllegalStateException("Production requires configured API credentials");
        }
        if (!redisTls) {
            throw new IllegalStateException("Production Redis connections must use TLS");
        }
    }
}
