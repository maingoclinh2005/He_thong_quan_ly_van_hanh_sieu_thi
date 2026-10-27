/// Client-side scheduling only; the API remains the authority for permissions.
class CacheSyncPolicy {
  static Set<String> resources({required bool authenticated, String? role}) => {
    'products',
    if (authenticated) 'profile',
    if (authenticated && (role == 'admin' || role == 'employee')) ...{
      'inventory',
      'history',
      'orders',
    },
    if (authenticated && role == 'admin') 'users',
  };
}
