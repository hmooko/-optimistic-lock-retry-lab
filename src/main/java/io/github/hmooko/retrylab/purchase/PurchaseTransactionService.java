package io.github.hmooko.retrylab.purchase;

import io.github.hmooko.retrylab.domain.Product;
import io.github.hmooko.retrylab.domain.ProductRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PurchaseTransactionService {
    private final ProductRepository productRepository;

    public PurchaseTransactionService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public void purchaseOptimistic(long productId) {
        Product product = productRepository.findById(productId)
                .orElseThrow(() -> notFound(productId));
        product.decreaseStock();
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public void purchasePessimistic(long productId) {
        Product product = productRepository.findByIdForUpdate(productId)
                .orElseThrow(() -> notFound(productId));
        product.decreaseStock();
    }

    private ResponseStatusException notFound(long productId) {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "product not found: " + productId);
    }
}
