package com.foundersync.post_service.controller;

import com.foundersync.post_service.entity.Comment;
import com.foundersync.post_service.service.CommentService;
import com.foundersync.post_service.security.AuthenticatedUser;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/posts")
@RequiredArgsConstructor
public class CommentController {

    private final CommentService commentService;

    @PostMapping("/{postId}/comments/{userId}")
    public ResponseEntity<Comment> addComment(
            @PathVariable UUID postId,
            @PathVariable UUID userId,
            @RequestBody String content,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(commentService.addComment(postId, userId, content));
    }

    // Reply to a comment
    @PostMapping("/{postId}/comments/{parentId}/reply/{userId}")
    public ResponseEntity<Comment> addReply(
            @PathVariable UUID postId,
            @PathVariable UUID parentId,
            @PathVariable UUID userId,
            @RequestBody String content,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(commentService.addReply(postId, parentId, userId, content));
    }

    @PutMapping("/comments/{commentId}")
    public ResponseEntity<Comment> updateComment(
            @PathVariable UUID commentId,
            @RequestBody String content,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        try {
            return ResponseEntity.ok(commentService.updateComment(commentId, content, user.getUserId()));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
    }

    @DeleteMapping("/comments/{commentId}")
    public ResponseEntity<Void> deleteComment(
            @PathVariable UUID commentId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        try {
            commentService.deleteComment(commentId, user.getUserId());
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{postId}/comments")
    public ResponseEntity<List<Comment>> getCommentsByPostId(@PathVariable UUID postId) {
        return ResponseEntity.ok(commentService.getCommentsByPostId(postId));
    }

    // Like a comment
    @PostMapping("/comments/{commentId}/like/{userId}")
    public ResponseEntity<String> likeComment(
            @PathVariable UUID commentId,
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(commentService.likeComment(commentId, userId));
    }

    // Unlike a comment
    @DeleteMapping("/comments/{commentId}/like/{userId}")
    public ResponseEntity<String> unlikeComment(
            @PathVariable UUID commentId,
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(commentService.unlikeComment(commentId, userId));
    }
}
