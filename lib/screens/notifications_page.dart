import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import 'home_page.dart'; // For OhtliSettings if needed

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<Map<String, dynamic>> _mockNotifications = [
    {
      'id': '1',
      'type': 'follow',
      'user': 'Juan Mendoza',
      'avatar': null,
      'initials': 'JM',
      'message': 'empezó a seguirte en tu camino.',
      'time': 'Hace 5 min',
      'isRead': false,
    },
    {
      'id': '2',
      'type': 'like',
      'user': 'Sofía Rubio',
      'avatar': null,
      'initials': 'SR',
      'message': 'le gustó tu crónica "Tacos, stickers y café".',
      'time': 'Hace 2 horas',
      'isRead': false,
    },
    {
      'id': '3',
      'type': 'title',
      'user': 'Ohtli',
      'avatar': 'assets/icon_isologo.svg',
      'initials': 'O',
      'message': '¡Felicidades! Desbloqueaste el título de "Ometeotl".',
      'time': 'Ayer',
      'isRead': true,
    },
    {
      'id': '4',
      'type': 'friend',
      'user': 'Carlos Pérez',
      'avatar': null,
      'initials': 'CP',
      'message': 'te añadió a su lista de amigos cercanos.',
      'time': 'Hace 3 días',
      'isRead': true,
    },
  ];

  void _markAllAsRead() {
    setState(() {
      for (var n in _mockNotifications) {
        n['isRead'] = true;
      }
    });
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
          'Notificaciones',
          style: GoogleFonts.outfit(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _markAllAsRead,
            child: Text(
              'Marcar todo como leído',
              style: GoogleFonts.inter(
                color: OhtliColors.stormyTeal,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _mockNotifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: isDark ? Colors.white24 : OhtliColors.cantera,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes notificaciones todavía.',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _mockNotifications.length,
              itemBuilder: (context, index) {
                final notification = _mockNotifications[index];
                final bool isRead = notification['isRead'] as bool;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isRead ? cardColor.withValues(alpha: 0.6) : cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRead
                          ? Colors.transparent
                          : OhtliColors.stormyTeal.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: isRead
                        ? []
                        : [
                            BoxShadow(
                              color: OhtliColors.stormyTeal.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: OhtliColors.stormyTeal,
                      ),
                      child: Center(
                        child: Text(
                          notification['initials'] as String,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    title: RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(color: textColor, fontSize: 13.5),
                        children: [
                          TextSpan(
                            text: '${notification['user']} ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: notification['message'] as String,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        notification['time'] as String,
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    trailing: !isRead
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: OhtliColors.xoconostle,
                            ),
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        notification['isRead'] = true;
                      });
                    },
                  ),
                );
              },
            ),
    );
  }
}
