/// A request to open the records page with a specific filter. Used by global
/// search, model/key drill-downs and future deep links.
class RecordsNavigationRequest {
  const RecordsNavigationRequest({
    this.tabIndex = 1,
    this.query = '',
    this.model = '',
    this.days,
    this.keyId,
    this.keyName = '',
  });

  final int tabIndex;
  final String query;
  final String model;
  final int? days;
  final String? keyId;
  final String keyName;
}

class RecordsFilterRequest {
  const RecordsFilterRequest({
    this.query = '',
    this.model = '',
    this.days,
    this.keyId,
    this.keyName = '',
  });

  final String query;
  final String model;
  final int? days;
  final String? keyId;
  final String keyName;
}
