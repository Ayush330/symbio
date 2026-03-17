import 'package:flutter/material.dart';

class Favour {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String text;
  final String category;
  final int points;
  final DateTime createdAt;

  Favour({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.text,
    required this.category,
    required this.points,
    required this.createdAt,
  });

  factory Favour.fromJson(Map<String, dynamic> json) {
    return Favour(
      id: json['id'],
      fromUserId: json['initiator_id'],
      toUserId: json['target_id'],
      text: json['text'] ?? '',
      category: json['category'] ?? 'other',
      points: json['points'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class RelationshipStats {
  final double score;
  final String color;
  final int totalGiven;
  final int totalReceived;
  final int pointsGiven;
  final int pointsReceived;
  final double karmaScore;

  RelationshipStats({
    required this.score,
    required this.color,
    required this.totalGiven,
    required this.totalReceived,
    required this.pointsGiven,
    required this.pointsReceived,
    required this.karmaScore,
  });

  factory RelationshipStats.fromJson(Map<String, dynamic> json) {
    return RelationshipStats(
      score: (json['score'] as num).toDouble(),
      color: json['color'],
      totalGiven: json['total_given'],
      totalReceived: json['total_received'],
      pointsGiven: json['points_given'],
      pointsReceived: json['points_received'],
      karmaScore: (json['karma_score'] as num?)?.toDouble() ?? 1.0,
    );
  }

}

class ProfileStats {
  final int totalFavoursGiven;
  final int totalFavoursReceived;
  final int totalPointsGiven;
  final int totalPointsReceived;
  final int netFavours;
  final int netPoints;
  final double karmaScore;

  ProfileStats({
    required this.totalFavoursGiven,
    required this.totalFavoursReceived,
    required this.totalPointsGiven,
    required this.totalPointsReceived,
    required this.netFavours,
    required this.netPoints,
    required this.karmaScore,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      totalFavoursGiven: json['total_favours_given'],
      totalFavoursReceived: json['total_favours_received'],
      totalPointsGiven: json['total_points_given'],
      totalPointsReceived: json['total_points_received'],
      netFavours: json['net_favours'] ?? 0,
      netPoints: json['net_points'] ?? 0,
      karmaScore: (json['karma_score'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class ActivityGraphData {
  final String name;
  final int points;

  ActivityGraphData({required this.name, required this.points});

  factory ActivityGraphData.fromJson(Map<String, dynamic> json) {
    return ActivityGraphData(
      name: json['name'],
      points: json['points'],
    );
  }
}
