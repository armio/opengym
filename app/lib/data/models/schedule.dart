import 'json.dart';

/// The `schedule` doc: per-date reschedules (`dayPlan`, specs/data-model.md §1.4.4).
class ScheduleDoc implements JsonModel {
  ScheduleDoc({Map<String, String>? dayPlan, JsonMap? extra}) : dayPlan = dayPlan ?? {}, extra = extra ?? {};

  factory ScheduleDoc.fromJson(Object? json) {
    final m = asMap(json);
    return ScheduleDoc(dayPlan: asStringMap(m['dayPlan']), extra: extraOf(m, const {'dayPlan'}));
  }

  /// `'YYYY-MM-DD'` → routine id or `'rest'`. A missing key follows the weekly plan.
  Map<String, String> dayPlan;
  JsonMap extra;

  ScheduleDoc copy() => ScheduleDoc.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'dayPlan': {...dayPlan},
  };
}
