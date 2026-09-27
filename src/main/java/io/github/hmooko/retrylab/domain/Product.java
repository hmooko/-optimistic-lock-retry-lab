package io.github.hmooko.retrylab.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "product")
public class Product {
    @Id
    private Long id;

    @Column(nullable = false)
    private long stock;

    @Version
    @Column(nullable = false)
    private Long version;

    protected Product() {}

    public Product(Long id, long stock) {
        this.id = id;
        this.stock = stock;
    }

    public void decreaseStock() {
        if (stock <= 0) {
            throw new IllegalStateException("out of stock: productId=" + id);
        }
        stock--;
    }

    public Long getId() { return id; }
    public long getStock() { return stock; }
    public Long getVersion() { return version; }
}
