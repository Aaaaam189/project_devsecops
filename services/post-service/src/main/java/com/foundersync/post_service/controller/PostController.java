package com.foundersync.post_service.controller;

import com.foundersync.post_service.dto.PostRequest;
import com.foundersync.post_service.dto.PostResponse;
import com.foundersync.post_service.security.AuthenticatedUser;
import com.foundersync.post_service.service.PostService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/posts")
@RequiredArgsConstructor
public class PostController {

    private final PostService postService;

    // Créer un post
    @PostMapping
    public ResponseEntity<PostResponse> createPost(
            @RequestBody PostRequest request,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        request.setUserId(user.getUserId());
        return ResponseEntity.status(HttpStatus.CREATED).body(postService.createPost(request));
    }

    // Modifier un post
    @PutMapping("/{id}")
    public ResponseEntity<PostResponse> updatePost(
            @PathVariable UUID id,
            @RequestBody PostRequest request,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        UUID authenticatedUserId = user.getUserId();
        PostResponse existing = postService.getPostById(id);
        if (!authenticatedUserId.equals(existing.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        request.setUserId(authenticatedUserId);
        return ResponseEntity.ok(postService.updatePost(id, request));
    }

    // Supprimer un post
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deletePost(
            @PathVariable UUID id,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        UUID authenticatedUserId = user.getUserId();
        PostResponse existing = postService.getPostById(id);
        if (!authenticatedUserId.equals(existing.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        postService.deletePost(id);
        return ResponseEntity.noContent().build();
    }

    // Consulter tous les posts
    @GetMapping
    public ResponseEntity<List<PostResponse>> getAllPosts(
            @RequestParam(required = false) UUID currentUserId) {
        if (currentUserId != null) {
            return ResponseEntity.ok(postService.getAllPosts(currentUserId));
        }
        return ResponseEntity.ok(postService.getAllPosts());
    }

    // Consulter un post
    @GetMapping("/{id}")
    public ResponseEntity<PostResponse> getPostById(@PathVariable UUID id) {
        return ResponseEntity.ok(postService.getPostById(id));
    }

    // Consulter les posts d'un utilisateur
    @GetMapping("/user/{userId}")
    public ResponseEntity<List<PostResponse>> getPostsByUserId(@PathVariable UUID userId) {
        return ResponseEntity.ok(postService.getPostsByUserId(userId));
    }
}