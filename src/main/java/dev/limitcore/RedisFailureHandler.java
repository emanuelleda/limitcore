package dev.limitcore;

import org.springframework.dao.DataAccessException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** Never turn infrastructure failures into positive quota decisions. */
@RestControllerAdvice
public class RedisFailureHandler {
    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<ProblemDetail> handleRedisError(DataAccessException cause) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE, "Limitação de requisições temporariamente indisponível");
        problem.setTitle("Dependência indisponível");
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .cacheControl(CacheControl.noStore())
                .body(problem);
    }
}
