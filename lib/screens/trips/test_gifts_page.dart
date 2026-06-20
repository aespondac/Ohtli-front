import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/trip_model.dart';
import '../../widgets/gift_wrapped_card.dart';
import '../../widgets/trip_card.dart';

class TestGiftsPage extends StatefulWidget {
  const TestGiftsPage({super.key});

  @override
  State<TestGiftsPage> createState() => _TestGiftsPageState();
}

class _TestGiftsPageState extends State<TestGiftsPage> {
  // Key to force rebuild all cards and reset the animation state
  Key _resetKey = UniqueKey();
  
  // Custom list of senders for variety
  final List<String> _senders = [
    "Alfredo Esponda",
    "Sofía Ramos",
    "Alejandro Ruiz",
    "Mariana Gómez",
    "Diego Peralta"
  ];

  // Map to hold unlock dates (some locked, some ready)
  final List<DateTime?> _dates = [
    DateTime.now(), // 0. Unlocked (Ready)
    DateTime.now().add(const Duration(days: 8)), // 1. Locked (8 days future)
    DateTime.now(), // 2. Unlocked (Ready)
    DateTime.now().add(const Duration(days: 3)), // 3. Locked (3 days future)
    DateTime.now(), // 4. Unlocked (Ready)
  ];

  void _resetGifts() {
    setState(() {
      _resetKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 1;
    if (screenWidth > 1200) {
      crossAxisCount = 3;
    } else if (screenWidth > 800) {
      crossAxisCount = 2;
    }

    final double availableWidth = screenWidth;
    final double padding = 24.0;
    
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 24) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1 
        ? 125.0 
        : (cardWidth * 9 / 16) + 168.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF0EEE9),
      appBar: AppBar(
        title: Text(
          'Muestra de Regalos por Abrir',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _resetGifts,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              'Resetear Envolturas',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Toca los regalos disponibles para ver la animación de desenvuelto.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            
            // Grid of gift wraps adapting to screen
            GridView.builder(
              key: _resetKey,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: computedAspectRatio,
              ),
              itemCount: 16,
              itemBuilder: (context, index) {
                final String tripId = "trip_$index";
                final String sender = _senders[index % _senders.length];
                final DateTime? unlockDate = _dates[index % _dates.length];
                
                // Determine if locked
                final bool isLocked = unlockDate != null && 
                    DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
                        .isBefore(DateTime(unlockDate.year, unlockDate.month, unlockDate.day));

                final mockTrip = Trip(
                  id: tripId,
                  userId: "mock_user",
                  title: "Aventura Sorpresa #$index",
                  description: "Preparado por $sender",
                  coverUrl: "",
                  status: "draft",
                  visibility: "private",
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                  isSurprise: true,
                  surpriseUnlockDate: unlockDate,
                );

                // Dummy card content revealed underneath
                final Widget cardContent = TripCard(
                  trip: mockTrip,
                  isHorizontal: crossAxisCount == 1,
                  addedByName: sender,
                  onEdit: () {},
                  onFeDeErratas: null,
                  onDelete: () {},
                );

                return GiftWrappedCard(
                  trip: mockTrip,
                  isLocked: false, // Override to allow testing unwrap animations locally
                  isOpened: false,
                  addedByName: sender,
                  onRevealComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('¡Sorpresa revelada! Trip ID: $tripId ($sender)'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: cardContent,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
