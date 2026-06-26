package {{ group_id }}.server;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Stub application endpoint. A basic service exposes a single route on the
 * service port that identifies itself, so it is a genuine long-lived HTTP
 * server rather than just a health responder. Replace with real application
 * routes as the service grows.
 */
@RestController
public class RootController {

    @GetMapping("/")
    public Map<String, String> root() {
        return Map.of(
            "service", "{{ project-name }}",
            "status", "ok"
        );
    }
}
