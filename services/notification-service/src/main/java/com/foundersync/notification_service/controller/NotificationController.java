package com.foundersync.notification_service.controller;

import com.foundersync.notification_service.entity.Notification;
import com.foundersync.notification_service.security.AuthenticatedUser;
import com.foundersync.notification_service.service.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;

    @GetMapping("/{userId}")
    public ResponseEntity<List<Notification>> getAll(
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(403).build();
        }
        return ResponseEntity.ok(notificationService.getAll(userId));
    }

    @GetMapping("/{userId}/unread")
    public ResponseEntity<List<Notification>> getUnread(
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(notificationService.getUnread(userId));
    }

    @GetMapping("/{userId}/unread/count")
    public ResponseEntity<Long> countUnread(
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(notificationService.countUnread(userId));
    }

    @PutMapping("/{id}/read")
    public ResponseEntity<Void> markAsRead(
            @PathVariable UUID id,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!notificationService.markAsRead(id, user.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{userId}/read-all")
    public ResponseEntity<Void> markAllAsRead(
            @PathVariable UUID userId,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!user.getUserId().equals(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        notificationService.markAllAsRead(userId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            @PathVariable UUID id,
            @RequestAttribute("authenticatedUser") AuthenticatedUser user) {
        if (!notificationService.delete(id, user.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.noContent().build();
    }
}