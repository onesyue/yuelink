/// 统一的异步操作状态枚举
enum ActionStatus { idle, loading, success, error }

/// 统一的异步操作状态机模型
/// 用于规范化 UI 层对异步操作（如切换节点、测速、保存配置）的状态管理，
/// 避免各页面重复编写 isLoading, isSuccess, errorMessage 等散落变量。
class ActionState<T> {
  final ActionStatus status;
  final T? data;
  final String? errorMessage;

  const ActionState({
    this.status = ActionStatus.idle,
    this.data,
    this.errorMessage,
  });

  const ActionState.idle() : this(status: ActionStatus.idle);
  
  const ActionState.loading() : this(status: ActionStatus.loading);
  
  const ActionState.success(T data) : this(status: ActionStatus.success, data: data);
  
  const ActionState.error(String message) : this(status: ActionStatus.error, errorMessage: message);

  bool get isIdle => status == ActionStatus.idle;
  bool get isLoading => status == ActionStatus.loading;
  bool get isSuccess => status == ActionStatus.success;
  bool get isError => status == ActionStatus.error;
}
