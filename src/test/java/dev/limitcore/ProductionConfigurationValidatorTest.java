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
            () -> new ProductionConfigurationValidator("some-strong-api-key", "", false));
    }

    @Test void allowsTenantCredentialsWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator("",
            "alpha=abcdefghijklmnop", true));
    }

    @Test void allowsLegacyCredentialWithTls() {
        assertDoesNotThrow(() -> new ProductionConfigurationValidator(
            "some-strong-api-key", "", true));
    }
}
