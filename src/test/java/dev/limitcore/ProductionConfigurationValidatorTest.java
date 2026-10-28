package dev.limitcore;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ProductionConfigurationValidatorTest {
    @Test void rejectsMissingCredentials() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator("", "", true, "redis-password-long"));
    }

    @Test void rejectsRedisWithoutTls() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator("s".repeat(32), "", false, "redis-password-long"));
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
            new ProductionConfigurationValidator("s".repeat(32), "", true, ""));
        assertTrue(error.getMessage().contains("Redis"));
    }

    @Test void rejectsWeakRedisPassword() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator("s".repeat(32), "", true, "short"));
    }

    @Test void allowsTenantCredentialsWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator("",
            "alpha=" + "a".repeat(32), true, "redis-password-long"));
    }

    @Test void allowsLegacyCredentialWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator(
            "s".repeat(32), "", true, "redis-password-long"));
    }
}
