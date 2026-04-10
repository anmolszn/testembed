class SimCard {
  final int slotIndex;
  final String carrierName;
  final int subscriptionId;
  final String phoneNumber;

  const SimCard({
    required this.slotIndex,
    required this.carrierName,
    required this.subscriptionId,
    required this.phoneNumber,
  });

  factory SimCard.fromMap(Map<dynamic, dynamic> map) => SimCard(
        slotIndex: map['slotIndex'] as int,
        carrierName: map['carrierName'] as String? ?? 'Unknown',
        subscriptionId: map['subscriptionId'] as int,
        phoneNumber: map['phoneNumber'] as String? ?? '',
      );

  String get displayName => carrierName.isNotEmpty ? carrierName : 'SIM ${slotIndex + 1}';
}
