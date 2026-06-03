import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _auth = AuthService();
  final TextEditingController _searchController = TextEditingController();
  bool _isSigningOut = false;
  String _query = '';
  String _selectedCategory = 'All';

  Stream<QuerySnapshot<Map<String, dynamic>>> get _listingsStream =>
      FirebaseFirestore.instance.collection('listings').snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _listingsStream,
              builder: (context, snapshot) {
                final listings =
                    (snapshot.data?.docs
                              .map(MarketplaceListing.fromFirestore)
                              .where((listing) => listing.isActive)
                              .toList() ??
                          <MarketplaceListing>[])
                      ..sort(_sortByNewest);
                final totalDocs = snapshot.data?.docs.length ?? 0;
                final categories = _categoriesFor(listings);
                final filteredListings = _filterListings(listings);
                final groupedListings = _groupListings(filteredListings);

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        isSigningOut: _isSigningOut,
                        listingCount: filteredListings.length,
                        latestListing: listings.isEmpty ? null : listings.first,
                        onLogout: _signOut,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SearchAndFilters(
                        controller: _searchController,
                        query: _query,
                        categories: categories,
                        selectedCategory: _selectedCategory,
                        onQueryChanged: (value) =>
                            setState(() => _query = value.trim()),
                        onCategorySelected: (value) =>
                            setState(() => _selectedCategory = value),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        listings.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _StateMessage(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load deals',
                          message: '${snapshot.error}',
                        ),
                      )
                    else if (filteredListings.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _StateMessage(
                          icon: Icons.search_off_rounded,
                          title: totalDocs == 0
                              ? 'No Firestore listings yet'
                              : 'No matching active deals',
                          message: totalDocs == 0
                              ? 'The app is connected to Firebase, but the listings collection returned 0 documents.'
                              : 'Firestore returned $totalDocs documents. Check search, category, or isActive values.',
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: groupedListings.length,
                        itemBuilder: (context, index) {
                          final group = groupedListings[index];
                          return _ListingDateGroup(group: group);
                        },
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<String> _categoriesFor(List<MarketplaceListing> listings) {
    final values =
        listings
            .map((listing) => listing.categoryLabel)
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  int _sortByNewest(MarketplaceListing left, MarketplaceListing right) {
    final leftDate = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return rightDate.compareTo(leftDate);
  }

  List<MarketplaceListing> _filterListings(List<MarketplaceListing> listings) {
    final normalizedQuery = _query.toLowerCase();

    return listings.where((listing) {
      final matchesCategory =
          _selectedCategory == 'All' ||
          listing.categoryLabel.toLowerCase() ==
              _selectedCategory.toLowerCase();
      if (!matchesCategory) return false;
      if (normalizedQuery.isEmpty) return true;

      final haystack = [
        listing.title,
        listing.description,
        listing.location,
        listing.categoryLabel,
        listing.matchedKeywords.join(' '),
      ].join(' ').toLowerCase();

      return haystack.contains(normalizedQuery);
    }).toList();
  }

  List<ListingDateGroup> _groupListings(List<MarketplaceListing> listings) {
    final groups = <String, List<MarketplaceListing>>{};

    for (final listing in listings) {
      final label = _dateLabel(listing.createdAt);
      groups.putIfAbsent(label, () => <MarketplaceListing>[]).add(listing);
    }

    return groups.entries
        .map((entry) => ListingDateGroup(entry.key, entry.value))
        .toList();
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Recently';
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final listingDay = DateTime(local.year, local.month, local.day);
    final difference = today.difference(listingDay).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return DateFormat('d MMMM').format(local);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isSigningOut,
    required this.listingCount,
    required this.latestListing,
    required this.onLogout,
  });

  final bool isSigningOut;
  final int listingCount;
  final MarketplaceListing? latestListing;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF101828),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF344054)),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFACC15),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AutoMarket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Live marketplace deal alerts',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Account',
                color: Colors.white,
                icon: isSigningOut
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
                      )
                    : const Icon(Icons.more_vert_rounded, color: Colors.white),
                onSelected: (value) {
                  if (value == 'logout') onLogout();
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
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Visible deals',
                  value: '$listingCount',
                  icon: Icons.local_offer_rounded,
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  label: 'Latest',
                  value: latestListing?.shortTime ?? '--',
                  icon: Icons.schedule_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2939),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF344054)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.query,
    required this.categories,
    required this.selectedCategory,
    required this.onQueryChanged,
    required this.onCategorySelected,
  });

  final TextEditingController controller;
  final String query;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search title, location, keyword',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = category == selectedCategory;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) => onCategorySelected(category),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF344054),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  selectedColor: const Color(0xFF0F766E),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFE4E7EC),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingDateGroup extends StatelessWidget {
  const _ListingDateGroup({required this.group});

  final ListingDateGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              group.label,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          ...group.listings.map(
            (listing) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DealCard(listing: listing),
            ),
          ),
        ],
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.listing});

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DealDetailScreen(listing: listing)),
        ),
        child: Container(
          height: 124,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF101828).withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Hero(
                tag: 'listing-image-${listing.id}',
                child: _ListingImage(
                  imageUrl: listing.imageUrl,
                  width: 96,
                  height: 100,
                  radius: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: _CategoryBadge(listing.categoryLabel)),
                        const SizedBox(width: 8),
                        Text(
                          listing.shortTime,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.place_rounded,
                                size: 16,
                                color: Color(0xFF667085),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  listing.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          listing.priceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF067647),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DealDetailScreen extends StatelessWidget {
  const DealDetailScreen({super.key, required this.listing});

  final MarketplaceListing listing;

  Future<void> _openMarketplace(BuildContext context) async {
    final uri = Uri.tryParse(listing.marketplaceUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marketplace link is missing.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Marketplace link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        IconButton.filled(
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Deal details',
                            style: TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'listing-image-${listing.id}',
                            child: _ListingImage(
                              imageUrl: listing.imageUrl,
                              width: double.infinity,
                              height: 290,
                              radius: 0,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: _CategoryBadge(
                                        listing.categoryLabel,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 16,
                                      color: Color(0xFF667085),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      listing.fullTime,
                                      style: const TextStyle(
                                        color: Color(0xFF667085),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  listing.title,
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    height: 1.12,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  listing.priceLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF067647),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _InfoRow(
                                  icon: Icons.place_rounded,
                                  label: listing.location,
                                ),
                                if (listing.description.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Text(
                                    listing.description,
                                    style: const TextStyle(
                                      color: Color(0xFF344054),
                                      fontSize: 16,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                                if (listing.matchedKeywords.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: listing.matchedKeywords
                                        .map(
                                          (keyword) => Chip(
                                            label: Text(keyword),
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor: const Color(
                                              0xFFEFF8FF,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFB2DDFF),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 22),
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: FilledButton.icon(
                                    onPressed: () => _openMarketplace(context),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: const Text('Open Marketplace'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF667085), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Text(
        label.isEmpty ? 'Marketplace' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFC2410C),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ListingImage extends StatelessWidget {
  const _ListingImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String imageUrl;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    if (imageUrl.isEmpty) {
      return _ImageFallback(width: width, height: height, radius: radius);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => _ImageFallback(
          width: width,
          height: height,
          radius: 0,
          loading: true,
        ),
        errorWidget: (_, _, _) =>
            _ImageFallback(width: width, height: height, radius: 0),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({
    required this.width,
    required this.height,
    required this.radius,
    this.loading = false,
  });

  final double width;
  final double height;
  final double radius;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F8),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : const Icon(
                Icons.image_not_supported_rounded,
                color: Color(0xFF98A2B3),
                size: 34,
              ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: const Color(0xFF667085)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.location,
    required this.categoryLabel,
    required this.description,
    required this.marketplaceUrl,
    required this.imageUrl,
    required this.matchedKeywords,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String priceLabel;
  final String location;
  final String categoryLabel;
  final String description;
  final String marketplaceUrl;
  final String imageUrl;
  final List<String> matchedKeywords;
  final bool isActive;
  final DateTime? createdAt;

  String get shortTime {
    if (createdAt == null) return 'Now';
    return DateFormat('h:mm a').format(createdAt!.toLocal());
  }

  String get fullTime {
    if (createdAt == null) return 'Recently';
    return DateFormat('MMM d, h:mm a').format(createdAt!.toLocal());
  }

  factory MarketplaceListing.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = _readString(data, 'title', fallback: 'Untitled listing');
    final description = _readString(
      data,
      'normalizedTitle',
      fallback: title,
    ).trim();
    final priceLabel = _readString(
      data,
      'priceLabel',
      fallback: _fallbackPriceLabel(data['price']),
    );

    return MarketplaceListing(
      id: doc.id,
      title: title,
      priceLabel: priceLabel,
      location: _readString(data, 'location', fallback: 'Unknown location'),
      categoryLabel: _readString(
        data,
        'categoryLabel',
        fallback: 'Marketplace',
      ),
      description: description == title ? '' : description,
      marketplaceUrl: _readString(data, 'marketplaceUrl'),
      imageUrl: _readString(data, 'imageUrl'),
      matchedKeywords: _readStringList(data['matchedKeywords']),
      isActive: data['isActive'] != false,
      createdAt: _readDate(data['createdAt']),
    );
  }

  static String _readString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static List<String> _readStringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      final milliseconds = value > 9999999999 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return null;
  }

  static String _fallbackPriceLabel(Object? value) {
    if (value == null) return 'Price hidden';
    if (value is num) return 'Rs. ${NumberFormat('#,##0').format(value)}';
    final text = value.toString().trim();
    return text.isEmpty ? 'Price hidden' : text;
  }
}

class ListingDateGroup {
  const ListingDateGroup(this.label, this.listings);

  final String label;
  final List<MarketplaceListing> listings;
}
