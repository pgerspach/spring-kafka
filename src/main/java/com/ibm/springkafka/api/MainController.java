package com.ibm.springkafka.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class MainController {

    @GetMapping("/health")
    public Map<String, String> getHealthCheck(){
        Map<String, String> health = new HashMap();
        health.put("health", "UP");
        return health;
    }
}
