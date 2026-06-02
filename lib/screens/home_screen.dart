import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _auth = AuthService();
  bool _isSigningOut = false;

  final List<TransactionGroup> _groups = const [
    TransactionGroup(
      date: 'Today',
      transactions: [
        TransactionItem(
          name: 'Eva Novak',
          locationOrStatus: 'location',
          amount: 5710.20,
          isPositive: true,
          avatarColor: Color(0xFFE7D3C8),
          avatarText: 'EN',
        ),
        TransactionItem(
          name: 'Binance',
          locationOrStatus: 'location',
          amount: 714.00,
          isPositive: true,
          avatarColor: Color(0xFF121212),
          logo: TransactionLogo.binance,
        ),
      ],
    ),
    TransactionGroup(
      date: 'Yesterday',
      transactions: [
        TransactionItem(
          name: 'Henrik Jansen',
          locationOrStatus: 'location',
          amount: 428.00,
          isPositive: true,
          avatarColor: Color(0xFFD8E7EA),
          avatarText: 'HJ',
        ),
        TransactionItem(
          name: 'Multiplex',
          locationOrStatus: 'Paid',
          amount: 124.55,
          isPositive: false,
          avatarColor: Color(0xFF151515),
          logo: TransactionLogo.multiplex,
        ),
        TransactionItem(
          name: 'Nike',
          locationOrStatus: 'Paid',
          amount: 328.96,
          isPositive: false,
          avatarColor: Color(0xFF050505),
          logo: TransactionLogo.nike,
        ),
      ],
    ),
    TransactionGroup(
      date: '19 November',
      transactions: [
        TransactionItem(
          name: 'Matteo Ricci',
          locationOrStatus: 'location',
          amount: 548.00,
          isPositive: true,
          avatarColor: Color(0xFFEFD4D8),
          avatarText: 'MR',
        ),
        TransactionItem(
          name: 'Megogo',
          locationOrStatus: 'location',
          amount: 847.20,
          isPositive: false,
          avatarColor: Color(0xFF121212),
          logo: TransactionLogo.megogo,
        ),
        TransactionItem(
          name: 'Emilia Costa',
          locationOrStatus: 'location',
          amount: 147.00,
          isPositive: true,
          avatarColor: Color(0xFFE8D8C9),
          avatarText: 'EC',
        ),
      ],
    ),
  ];

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);

    try {
      await _auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $error')));
      setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF96D8C9),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            constraints: const BoxConstraints(maxWidth: 470),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(58),
                topRight: Radius.circular(58),
                bottomLeft: Radius.circular(58),
                bottomRight: Radius.circular(58),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE6F8F2),
                  Color(0xFFDFF1D7),
                  Color(0xFFC8F0E3),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withValues(alpha: 0.12),
                  blurRadius: 26,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(58),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 18),
                    child: Row(
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Account',
                          icon: _isSigningOut
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.arrow_back_ios_new_rounded),
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onSelected: (value) {
                            if (value == 'logout') _signOut();
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(Icons.logout_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('Logout'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Expanded(
                          child: Text(
                            'AutoMarket',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          tooltip: 'Search',
                          icon: const Icon(
                            Icons.search_rounded,
                            color: Colors.black,
                            size: 31,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 72, 24, 28),
                      itemCount: _groups.length,
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        return _TransactionGroupView(group: group);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionGroupView extends StatelessWidget {
  const _TransactionGroupView({required this.group});

  final TransactionGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(
            group.date,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.58),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        ...group.transactions.map(
          (tx) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TransactionTile(transaction: tx),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final TransactionItem transaction;

  @override
  Widget build(BuildContext context) {
    final amountColor = transaction.isPositive
        ? const Color(0xFF1F7938)
        : const Color(0xFF7A0710);

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.52),
            blurRadius: 18,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _TransactionAvatar(transaction: transaction),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        transaction.locationOrStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: transaction.locationOrStatus == 'Paid'
                              ? const Color(0xFF1E1717)
                              : Colors.black.withValues(alpha: 0.52),
                          fontSize: 15,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.history_rounded,
                      color: Colors.black.withValues(alpha: 0.46),
                      size: 17,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${transaction.isPositive ? '+' : '-'}Rs.${transaction.amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: amountColor,
                fontSize: 19,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionAvatar extends StatelessWidget {
  const _TransactionAvatar({required this.transaction});

  final TransactionItem transaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: transaction.avatarColor,
        shape: BoxShape.circle,
      ),
      child: Center(child: _buildAvatarContent()),
    );
  }

  Widget _buildAvatarContent() {
    switch (transaction.logo) {
      case TransactionLogo.binance:
        return const Icon(
          Icons.currency_bitcoin_rounded,
          color: Color(0xFFE5BD4B),
          size: 27,
        );
      case TransactionLogo.multiplex:
        return Container(
          width: 28,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFC91826),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text(
            'multi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 6,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case TransactionLogo.nike:
        return const Text(
          'Nike',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        );
      case TransactionLogo.megogo:
        return Container(
          width: 27,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF58C8C5),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      case null:
        return Text(
          transaction.avatarText,
          style: const TextStyle(
            color: Color(0xFF2B241F),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        );
    }
  }
}

class TransactionGroup {
  const TransactionGroup({required this.date, required this.transactions});

  final String date;
  final List<TransactionItem> transactions;
}

class TransactionItem {
  const TransactionItem({
    required this.name,
    required this.locationOrStatus,
    required this.amount,
    required this.isPositive,
    required this.avatarColor,
    this.avatarText = '',
    this.logo,
  });

  final String name;
  final String locationOrStatus;
  final double amount;
  final bool isPositive;
  final Color avatarColor;
  final String avatarText;
  final TransactionLogo? logo;
}

enum TransactionLogo { binance, multiplex, nike, megogo }
