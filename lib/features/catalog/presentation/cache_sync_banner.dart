import 'package:flutter/material.dart';
import '../data/store_cache_repository.dart';

class CacheSyncBanner extends StatelessWidget {
  const CacheSyncBanner({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: StoreCacheRepository.coordinator,
    builder: (context, _) => StoreCacheRepository.coordinator.errors.isEmpty
        ? const SizedBox.shrink()
        : Material(
            color: Colors.amber.shade100,
            child: ListTile(
              leading: const Icon(Icons.sync_problem),
              title: const Text(
                'Dữ liệu cục bộ chưa đồng bộ. Không gửi lại giao dịch chỉ vì lỗi này.',
              ),
              trailing: IconButton(
                tooltip: 'Đồng bộ lại',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    StoreCacheRepository.refreshAfterWrite(warehouse: true),
              ),
            ),
          ),
  );
}
