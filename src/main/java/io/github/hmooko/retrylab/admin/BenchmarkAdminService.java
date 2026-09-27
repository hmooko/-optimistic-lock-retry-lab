package io.github.hmooko.retrylab.admin;

import io.github.hmooko.retrylab.domain.Product;
import io.github.hmooko.retrylab.domain.ProductRepository;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class BenchmarkAdminService {
    private final ProductRepository productRepository;

    public BenchmarkAdminService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    @Transactional
    public void reset(int productCount, long stock) {
        if (productCount <= 0) throw new IllegalArgumentException("productCount must be > 0");
        if (stock <= 0) throw new IllegalArgumentException("stock must be > 0");

        productRepository.deleteAllInBatch();

        List<Product> products = new ArrayList<>(productCount);
        for (long id = 1; id <= productCount; id++) {
            products.add(new Product(id, stock));
        }

        productRepository.saveAll(products);
        productRepository.flush();
    }
}
