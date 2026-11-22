package com.foundersync.post_service.controller;

import com.foundersync.post_service.service.LikeService;
import com.foundersync.post_service.security.AuthenticatedUser;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/posts")
@RequiredArgsConstructor
public class LikeController {

    private final LikeService likeService;

    // Liker un post
    @PostMapping("/{postId}/like/{userId}")
    public ResponseEntity<String> likePost(
            @PathVariable UUID postId,
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(org.springframework.http.HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(likeService.likePost(postId, userId));
    }

    // Unliker un post
    @DeleteMapping("/{postId}/like/{userId}")
    public ResponseEntity<String> unlikePost(
            @PathVariable UUID postId,
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(org.springframework.http.HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(likeService.unlikePost(postId, userId));
    }
}