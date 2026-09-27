package io.github.hmooko.retrylab.admin;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class BenchmarkAdminController {
    private final BenchmarkAdminService benchmarkAdminService;

    public BenchmarkAdminController(BenchmarkAdminService benchmarkAdminService) {
        this.benchmarkAdminService = benchmarkAdminService;
    }

    @PostMapping("/reset")
    public ResponseEntity<Map<String, Object>> reset(
            @RequestParam(defaultValue = "100") int productCount,
            @RequestParam(defaultValue = "1000000") long stock
    ) {
        benchmarkAdminService.reset(productCount, stock);
        return ResponseEntity.ok(Map.of("productCount", productCount, "stock", stock));
    }
}
