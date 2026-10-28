package dev.limitcore;

import java.nio.charset.StandardCharsets;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockFilterChain;
import static org.junit.jupiter.api.Assertions.*;

class RequestBodyLimitFilterTest {
    private static MockHttpServletRequest request(byte[] body) {
        var request = new MockHttpServletRequest("POST", "/v1/limits/check");
        request.setServletPath("/v1/limits/check");
        request.setContentType("application/json");
        request.setContent(body);
        return request;
    }

    @Test void rejectsOversizedJsonBeforeController() throws Exception {
        var response = new MockHttpServletResponse();
        var chain = new MockFilterChain();
        new RequestBodyLimitFilter().doFilter(request(new byte[1025]), response, chain);
        assertEquals(413, response.getStatus());
        assertNull(chain.getRequest());
    }

    @Test void allowsAndPreservesNormalJson() throws Exception {
        var response = new MockHttpServletResponse();
        var chain = new MockFilterChain();
        byte[] payload = "{\"key\":\"safe\"}".getBytes(StandardCharsets.UTF_8);
        new RequestBodyLimitFilter().doFilter(request(payload), response, chain);
        assertNotNull(chain.getRequest());
        var wrapped = (HttpServletRequest) chain.getRequest();
        assertArrayEquals(payload, wrapped.getInputStream().readAllBytes());
        assertEquals(payload.length, wrapped.getContentLengthLong());
    }

    @Test void doesNotAffectHealthProbes() throws Exception {
        var request = new MockHttpServletRequest("GET", "/actuator/health");
        request.setServletPath("/actuator/health");
        var chain = new MockFilterChain();
        new RequestBodyLimitFilter().doFilter(request, new MockHttpServletResponse(), chain);
        assertSame(request, chain.getRequest());
    }
}
