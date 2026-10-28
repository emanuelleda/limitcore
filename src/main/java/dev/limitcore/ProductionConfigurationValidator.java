package dev.limitcore;

import org.springframework.beans.factory.annotation.Value;
import java.nio.charset.StandardCharsets;
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
        if (apiKey != null && !apiKey.isBlank() && apiKey.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("Production API credentials must have at least 32 UTF-8 bytes");
        }
        if (tenants != null && !tenants.isBlank()) {
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
        if (!redisTls) {
            throw new IllegalStateException("Production Redis connections must use TLS");
        }
    }
}
