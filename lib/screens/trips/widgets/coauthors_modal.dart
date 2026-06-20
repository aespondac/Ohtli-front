import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/colors.dart';

class CoAuthorsModal extends StatefulWidget {
  final List<String> initialCoAuthorIds;
  final List<String> originalCoAuthorIds;
  final List<String> initialCoAuthorNames;
  final bool initialIsSurprise;
  final List<String> initialSurpriseTargetIds;
  final List<String> initialSurpriseTargetNames;
  final Map<String, DateTime> initialSurpriseUnlockDates;
  final bool initialUnlockOnPublish;
  final List<Map<String, dynamic>> friendsList;
  final String status;

  const CoAuthorsModal({
    super.key,
    required this.initialCoAuthorIds,
    required this.originalCoAuthorIds,
    required this.initialCoAuthorNames,
    required this.initialIsSurprise,
    required this.initialSurpriseTargetIds,
    required this.initialSurpriseTargetNames,
    required this.initialSurpriseUnlockDates,
    required this.initialUnlockOnPublish,
    required this.friendsList,
    required this.status,
  });

  @override
  State<CoAuthorsModal> createState() => _CoAuthorsModalState();
}

class _CoAuthorsModalState extends State<CoAuthorsModal> {
  late List<String> tempCoAuthorIds;
  late List<String> tempCoAuthorNames;
  late bool tempIsSurprise;
  late List<String> tempSurpriseTargetIds;
  late List<String> tempSurpriseTargetNames;
  late Map<String, DateTime> tempSurpriseUnlockDates;
  late bool tempUnlockOnPublish;

  bool _useGlobalDate = false;
  DateTime? _globalUnlockDate;

  @override
  void initState() {
    super.initState();
    tempCoAuthorIds = List.from(widget.initialCoAuthorIds);
    tempCoAuthorNames = List.from(widget.initialCoAuthorNames);
    tempIsSurprise = widget.initialIsSurprise;
    tempSurpriseTargetIds = List.from(widget.initialSurpriseTargetIds);
    tempSurpriseTargetNames = List.from(widget.initialSurpriseTargetNames);
    tempSurpriseUnlockDates = Map.from(widget.initialSurpriseUnlockDates);
    tempUnlockOnPublish = widget.initialUnlockOnPublish;
  }

  void _onFriendTapped(String friendId, String friendName, bool isMutualCloseFriend) {
    if (widget.status == 'published' && widget.originalCoAuthorIds.contains(friendId)) {
      return; 
    }

    setState(() {
      if (tempCoAuthorIds.contains(friendId)) {
        tempCoAuthorIds.remove(friendId);
        tempCoAuthorNames.remove(friendName);
        if (isMutualCloseFriend && widget.status == 'draft') {
          tempSurpriseTargetIds.add(friendId);
          tempSurpriseTargetNames.add(friendName);
          tempIsSurprise = true;
          if (_useGlobalDate && _globalUnlockDate != null) {
            tempSurpriseUnlockDates[friendId] = _globalUnlockDate!;
          } else {
            tempSurpriseUnlockDates[friendId] = DateTime.now().add(const Duration(days: 1));
          }
        }
      } else if (tempSurpriseTargetIds.contains(friendId)) {
        tempSurpriseTargetIds.remove(friendId);
        tempSurpriseTargetNames.remove(friendName);
        tempSurpriseUnlockDates.remove(friendId);
        if (tempSurpriseTargetIds.isEmpty) tempIsSurprise = false;
      } else {
        tempCoAuthorIds.add(friendId);
        tempCoAuthorNames.add(friendName);
      }
    });
  }

  Widget _buildAvatarStateIndicator(String friendId) {
    final bool isNormal = tempCoAuthorIds.contains(friendId);
    final bool isSurprise = tempSurpriseTargetIds.contains(friendId);
    final bool isOriginal = widget.originalCoAuthorIds.contains(friendId);
    final bool isRemoved = isOriginal && !isNormal && !isSurprise;

    if (isNormal) {
      return Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: OhtliColors.stormyTeal, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 10),
        ),
      );
    } else if (isSurprise) {
      return Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: OhtliColors.stormyTeal, shape: BoxShape.circle),
          child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 10),
        ),
      );
    } else if (isRemoved) {
      return Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: OhtliColors.xoconostle, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 10),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFriendItem(Map<String, dynamic> friend, {bool vertical = true}) {
    final String friendId = friend['uid'];
    final String friendName = friend['displayName'];
    final bool isMutualCloseFriend = friend['isMutualCloseFriend'] == true;
    final String? photoURL = friend['photoURL'];
    final String initials = friendName.isNotEmpty ? friendName[0].toUpperCase() : '';

    final bool isNormal = tempCoAuthorIds.contains(friendId);
    final bool isSurprise = tempSurpriseTargetIds.contains(friendId);
    final bool isOriginal = widget.originalCoAuthorIds.contains(friendId);
    final bool isRemoved = isOriginal && !isNormal && !isSurprise;
    
    Color borderColor = Colors.transparent;
    Color bgColor = Colors.transparent;
    if (isNormal || isSurprise) {
      borderColor = OhtliColors.stormyTeal.withValues(alpha: 0.5);
      bgColor = OhtliColors.stormyTeal.withValues(alpha: 0.05);
    } else if (isRemoved) {
      borderColor = OhtliColors.xoconostle.withValues(alpha: 0.5);
      bgColor = OhtliColors.xoconostle.withValues(alpha: 0.05);
    }

    final avatar = Stack(
      children: [
        CircleAvatar(
          radius: vertical ? 16 : 22,
          backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.2),
          backgroundImage: (photoURL != null && photoURL.isNotEmpty) ? NetworkImage(photoURL) : null,
          child: (photoURL == null || photoURL.isEmpty)
              ? Text(initials, style: GoogleFonts.inter(fontSize: vertical ? 12 : 16, fontWeight: FontWeight.bold, color: OhtliColors.stormyTeal))
              : null,
        ),
        _buildAvatarStateIndicator(friendId),
      ],
    );

    if (!vertical) {
      return GestureDetector(
        onTap: () => _onFriendTapped(friendId, friendName, isMutualCloseFriend),
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              const SizedBox(height: 4),
              SizedBox(
                width: 50,
                child: Text(
                  friendName.split(' ')[0],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: OhtliColors.onyx),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _onFriendTapped(friendId, friendName, isMutualCloseFriend),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(friendName, style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx, fontWeight: FontWeight.w500)),
                ),
                if (isMutualCloseFriend)
                  Icon(Icons.star_rounded, size: 14, color: OhtliColors.stormyTeal.withValues(alpha: 0.5)),
              ],
            ),
            if (isSurprise && !_useGlobalDate && !_tempUnlockOnPublishChecked)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 44),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 12, color: OhtliColors.stormyTeal),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempSurpriseUnlockDates[friendId] ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            tempSurpriseUnlockDates[friendId] = picked;
                          });
                        }
                      },
                      child: Text(
                        tempSurpriseUnlockDates[friendId] != null
                            ? '${tempSurpriseUnlockDates[friendId]!.day}/${tempSurpriseUnlockDates[friendId]!.month}/${tempSurpriseUnlockDates[friendId]!.year}'
                            : 'Configurar fecha...',
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.stormyTeal, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _tempUnlockOnPublishChecked => tempUnlockOnPublish;

  @override
  Widget build(BuildContext context) {
    final actualFriends = widget.friendsList.where((f) => f['isFriend'] == true).toList();
    // For recent coauthors, we might just use the first few friends for now as a mock, or actualFriends if small
    final recentFriends = actualFriends.take(10).toList();

    return AlertDialog(
      backgroundColor: OhtliColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Co-autores del Plan',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
      ),
      content: SizedBox(
        width: 450,
        height: 600,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recentFriends.isNotEmpty) ...[
                      Text('Co-Autores Recientes', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 70,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: recentFriends.length,
                          itemBuilder: (context, idx) => _buildFriendItem(recentFriends[idx], vertical: false),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: OhtliColors.cantera.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                    ],
                    
                    Text('Lista de Amigos', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    if (actualFriends.isEmpty)
                      Text('Aún no tienes amigos.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic))
                    else
                      ...actualFriends.map((f) => _buildFriendItem(f, vertical: true)),
                    
                    const SizedBox(height: 16),
                    Divider(color: OhtliColors.cantera.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),

                    Text('Co-Autores Actuales', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    if (tempCoAuthorIds.isEmpty && tempSurpriseTargetIds.isEmpty)
                      Text('No has seleccionado a nadie.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...tempCoAuthorNames.map((n) => Chip(
                                label: Text(n, style: GoogleFonts.inter(fontSize: 11, color: Colors.white)),
                                backgroundColor: OhtliColors.stormyTeal,
                                side: BorderSide.none,
                              )),
                          ...tempSurpriseTargetNames.map((n) => Chip(
                                avatar: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 12),
                                label: Text(n, style: GoogleFonts.inter(fontSize: 11, color: Colors.white)),
                                backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.8),
                                side: BorderSide.none,
                              )),
                        ],
                      ),
                      if (tempIsSurprise) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: OhtliColors.stormyTeal.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Configuración de Sorpresa', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.stormyTeal)),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: Text('Abrir al publicar', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx)),
                                value: tempUnlockOnPublish,
                                activeColor: OhtliColors.stormyTeal,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  setState(() {
                                    tempUnlockOnPublish = val;
                                  });
                                },
                              ),
                              if (!tempUnlockOnPublish)
                                SwitchListTile(
                                  title: Text('Usar la misma fecha para todos', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx)),
                                  value: _useGlobalDate,
                                  activeColor: OhtliColors.stormyTeal,
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (val) async {
                                    setState(() {
                                      _useGlobalDate = val;
                                    });
                                    if (val && _globalUnlockDate == null) {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now().add(const Duration(days: 1)),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          _globalUnlockDate = picked;
                                          for (var id in tempSurpriseTargetIds) {
                                            tempSurpriseUnlockDates[id] = picked;
                                          }
                                        });
                                      } else {
                                        setState(() {
                                          _useGlobalDate = false;
                                        });
                                      }
                                    } else if (val && _globalUnlockDate != null) {
                                      setState(() {
                                        for (var id in tempSurpriseTargetIds) {
                                          tempSurpriseUnlockDates[id] = _globalUnlockDate!;
                                        }
                                      });
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'coAuthorIds': tempCoAuthorIds,
              'coAuthorNames': tempCoAuthorNames,
              'isSurprise': tempIsSurprise,
              'surpriseTargetIds': tempSurpriseTargetIds,
              'surpriseTargetNames': tempSurpriseTargetNames,
              'surpriseUnlockDates': tempSurpriseUnlockDates,
              'unlockOnPublish': tempUnlockOnPublish,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: OhtliColors.stormyTeal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Guardar', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
