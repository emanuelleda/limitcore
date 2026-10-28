package dev.limitcore;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ProductionConfigurationValidatorTest {
    @Test void rejectsMissingCredentials() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator("", "", true));
    }

    @Test void rejectsRedisWithoutTls() {
        assertThrows(IllegalStateException.class,
            () -> new ProductionConfigurationValidator("s".repeat(32), "", false));
    }

    @Test void rejectsWeakLegacyCredential() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator("short", "", true));
    }

    @Test void rejectsWeakTenantCredential() {
        assertThrows(IllegalStateException.class, () ->
            new ProductionConfigurationValidator("", "alpha=abcdefghijklmnop", true));
    }

    @Test void allowsTenantCredentialsWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator("",
            "alpha=" + "a".repeat(32), true));
    }

    @Test void allowsLegacyCredentialWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator(
            "s".repeat(32), "", true));
    }
}
