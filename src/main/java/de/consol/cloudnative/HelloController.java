package de.consol.cloudnative;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {
    @Autowired
    private Environment environment;

    private int invokedCount = 0;

    final String hostname = System.getenv().getOrDefault("HOSTNAME", "unknown");

    @RequestMapping("/")
    public String sayHello() {
        final String greeting = environment.getProperty("GREETING", "Hi");
        final String msg = String.format("%s (%s, %s)", greeting, invokedCount++, hostname);
        System.out.println(msg);
        return msg;
    }

    @GetMapping(value = "/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.status(HttpStatus.OK).body("Up and running");
    }
}
