import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import 'home_page.dart'; // For OhtliSettings if needed

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _mockFriends = [
    {
      'name': 'Juan Mendoza',
      'title': 'Explorador',
      'initials': 'JM',
      'isCloseFriend': false,
      'isFollowing': true,
    },
    {
      'name': 'Sofía Rubio',
      'title': 'Cronista Destacada',
      'initials': 'SR',
      'isCloseFriend': true,
      'isFollowing': true,
    },
    {
      'name': 'Carlos Pérez',
      'title': 'Viajero',
      'initials': 'CP',
      'isCloseFriend': false,
      'isFollowing': true,
    },
  ];

  final List<Map<String, dynamic>> _mockSuggested = [
    {
      'name': 'Mariana Gómez',
      'title': 'Nómada del Asfalto',
      'initials': 'MG',
      'isFollowing': false,
    },
    {
      'name': 'Daniel Ortega',
      'title': 'Aventurero CDMX',
      'initials': 'DO',
      'isFollowing': false,
    },
    {
      'name': 'Valeria Ramos',
      'title': 'Fotógrafa Ohtli',
      'initials': 'VR',
      'isFollowing': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color bgColor = isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer;
    final Color cardColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final Color textColor = isDark ? Colors.white : OhtliColors.onyx;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Amigos',
          style: GoogleFonts.outfit(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: OhtliColors.stormyTeal,
          labelColor: OhtliColors.stormyTeal,
          unselectedLabelColor: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.5),
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
          unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13.5),
          tabs: const [
            Tab(text: 'Tus Amigos'),
            Tab(text: 'Sugeridos'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar aventureros...',
                hintStyle: GoogleFonts.inter(
                  color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.5),
                  size: 20,
                ),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              style: GoogleFonts.inter(color: textColor, fontSize: 13),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(_mockFriends, cardColor, textColor, isDark, isSuggested: false),
                _buildFriendsList(_mockSuggested, cardColor, textColor, isDark, isSuggested: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList(
    List<Map<String, dynamic>> list,
    Color cardColor,
    Color textColor,
    bool isDark, {
    required bool isSuggested,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final friend = list[index];
        final bool isFollowing = friend['isFollowing'] as bool;
        final bool isCloseFriend = friend['isCloseFriend'] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: OhtliColors.stormyTeal,
                ),
                child: Center(
                  child: Text(
                    friend['initials'] as String,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          friend['name'] as String,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (isCloseFriend) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, color: Color(0xFF10B981), size: 14),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      friend['title'] as String,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    friend['isFollowing'] = !isFollowing;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFollowing ? OhtliColors.cantera : OhtliColors.stormyTeal,
                  foregroundColor: isFollowing ? OhtliColors.onyx : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: Text(
                  isFollowing ? 'Siguiendo' : 'Seguir',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
