package io.github.hmooko.retrylab;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class RetryLabApplication {
    public static void main(String[] args) {
        SpringApplication.run(RetryLabApplication.class, args);
    }
}
