package dev.limitcore;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ProductionConfigurationValidatorTest {
    private static final String STRONG_API_KEY = "0123456789abcdef0123456789abcdef";
    private static final String STRONG_TENANT = "alpha=0123456789abcdef0123456789abcdef";
    @Test void rejectsMissingCredentials() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator("", "", true, "redis-password-long"));
    }

    @Test void rejectsRedisWithoutTls() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator(STRONG_API_KEY, "", false, "redis-password-long"));
    }

    @Test void rejectsWeakLegacyCredential() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator("short", "", true, "redis-password-long"));
    }

    @Test void rejectsWeakTenantCredential() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator("", "alpha=abcdefghijklmnop", true, "redis-password-long"));
    }

    @Test void rejectsRedisWithoutAuthentication() {
        var error = assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator(STRONG_API_KEY, "", true, ""));
        assertTrue(error.getMessage().contains("Redis"));
    }

    @Test void rejectsWeakRedisPassword() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator(STRONG_API_KEY, "", true, "short"));
    }

    @Test void allowsTenantCredentialsWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator("",
            STRONG_TENANT, true, "redis-password-long"));
    }

    @Test void allowsLegacyCredentialWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator(
            STRONG_API_KEY, "", true, "redis-password-long"));
    }
}
