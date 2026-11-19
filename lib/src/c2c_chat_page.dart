import 'i18n/client_messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'app_scope.dart';
import 'auth/auth_sheet.dart' show AuthSheet;
import 'ui/client_components.dart' show clientText;
import 'app_state.dart';
import 'c2c_models.dart';
import 'models.dart';
import 'ui/theme/tokens.dart';

class C2cMessagingPage extends StatelessWidget {
  const C2cMessagingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final owner = state.session?.user.userId;
    if (owner == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 44),
            const SizedBox(height: 16),
            const LText('登录后查看 C2C 会话与订单'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AuthSheet(),
              ),
              child: const LText('登录'),
            ),
          ],
        ),
      );
    }
    return _Inbox(key: ValueKey(owner), state: state, owner: owner);
  }
}

class _Inbox extends StatefulWidget {
  const _Inbox({super.key, required this.state, required this.owner});
  final AppState state;
  final int owner;
  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  final search = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? events;
  Timer? debounce;
  List<C2cConversation> conversations = [];
  List<Map<String, dynamic>> orders = [];
  bool enabled = false,
      loading = true,
      more = false,
      opening = false,
      started = false;
  int tab = 0, generation = 0, offset = 0;
  String? error;
  bool roomOpen = false;
  bool get current =>
      mounted && widget.state.session?.user.userId == widget.owner;
  @override
  void initState() {
    super.initState();
    events = widget.state.realtime.c2cEvents(widget.owner).listen((event) {
      if (event['op'] == 'c2c.changed') {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 300), () => load());
      } else if (event['op'] == 'c2c.error' && current && !roomOpen) {
        setState(() {
          started = false;
          error = '聊天订阅未完成，请重试';
        });
      }
    });
    unawaited(load());
  }

  Future<void> load({bool append = false}) async {
    final run = ++generation;
    if (current) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final status = await widget.state.api.c2cStatus();
      if (!current || run != generation) return;
      if (status['runtimeEnabled'] is! bool) {
        throw const FormatException('C2C 状态资料不完整');
      }
      enabled = status['runtimeEnabled'] == true;
      if (!enabled) {
        setState(() => loading = false);
        return;
      }
      if (!started) {
        widget.state.realtime.watchC2c(owner: widget.owner);
        started = true;
      }
      if (tab == 0) {
        final page = await widget.state.api.c2cConversations(
          widget.owner,
          search: search.text,
          offset: append ? offset : 0,
        );
        if (!current || run != generation) return;
        setState(() {
          conversations = {
            for (final c in [
              ...(append ? conversations : <C2cConversation>[]),
              ...page.items,
            ])
              c.id: c,
          }.values.toList();
          offset = (append ? offset : 0) + page.items.length;
          more = page.hasMore;
        });
      } else {
        final page = await widget.state.api.c2cOrders(
          widget.owner,
          offset: append ? offset : 0,
        );
        if (!current || run != generation) return;
        final items = asList(page['items']).map(asMap).toList();
        setState(() {
          orders = [...(append ? orders : <Map<String, dynamic>>[]), ...items];
          offset = (append ? offset : 0) + items.length;
          more = page['hasMore'] == true;
        });
      }
    } catch (failure) {
      if (current && run == generation) {
        setState(() => error = clientErrorMessage(failure));
      }
    } finally {
      if (current && run == generation) setState(() => loading = false);
    }
  }

  Future<void> room(C2cConversation conversation) async {
    roomOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => C2cChatRoom(
            state: widget.state,
            owner: widget.owner,
            conversation: conversation,
          ),
        ),
      );
    } finally {
      roomOpen = false;
    }
    if (current) {
      widget.state.realtime.watchC2c(owner: widget.owner);
      await load();
    }
  }

  Future<void> openOrder(String id) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final conversation = await widget.state.api.c2cStart(
        widget.owner,
        orderId: id,
      );
      if (current) await room(conversation);
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => opening = false);
    }
  }

  Future<void> consult() async {
    final input = TextEditingController();
    String? problem;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LText('咨询商家'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                maxLength: 19,
                decoration: InputDecoration(
                  labelText: clientLabel(context, '商家 UID'),
                ),
              ),
              const LText('咨询遵循对方的隐私设置。订单会话请从订单进入。'),
              if (problem != null)
                LText(
                  problem!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const LText('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!RegExp(
                        r'^[1-9][0-9]{0,18}$',
                      ).hasMatch(input.text.trim())) {
                        update(() => problem = '请输入有效的商家 UID');
                        return;
                      }
                      update(() => busy = true);
                      try {
                        final conversation = await widget.state.api.c2cStart(
                          widget.owner,
                          targetUserId: input.text.trim(),
                        );
                        if (!current || !dialog.mounted) return;
                        Navigator.pop(dialog);
                        unawaited(room(conversation));
                      } catch (failure) {
                        if (dialog.mounted) {
                          update(() => problem = clientErrorMessage(failure));
                        }
                      } finally {
                        if (dialog.mounted) update(() => busy = false);
                      }
                    },
              child: LText(busy ? '打开中…' : '打开会话'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    unawaited(events?.cancel());
    widget.state.realtime.stopC2c(widget.owner);
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.state.language;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: LText(
                  clientText(language, 'C2C 消息与订单', 'C2C messages & orders'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: enabled ? consult : null,
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: clientLabel(context, '咨询商家'),
              ),
              IconButton(
                onPressed: loading ? null : () => load(),
                icon: const Icon(Icons.refresh),
                tooltip: clientLabel(context, '刷新'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: LText(clientText(language, '会话', 'Messages')),
              ),
              ButtonSegment(
                value: 1,
                label: LText(clientText(language, '订单', 'Orders')),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (value) {
              setState(() => tab = value.single);
              unawaited(load());
            },
          ),
        ),
        if (tab == 0 && enabled)
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: clientLabel(context, '搜索会话'),
              ),
              onChanged: (_) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 250),
                  () => load(),
                );
              },
            ),
          ),
        if (error != null)
          MaterialBanner(
            content: LText(
              error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              TextButton(onPressed: () => load(), child: const LText('重试')),
            ],
          ),
        Expanded(
          child: loading && conversations.isEmpty && orders.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : !enabled
              ? Center(
                  child: LText(error == null ? 'C2C 聊天暂未开启' : '暂时无法加载 C2C'),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (tab == 0 && conversations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: LText(
                            '暂无会话，可从订单联系对方或咨询商家。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (tab == 0)
                        for (final conversation in conversations)
                          ListTile(
                            key: ValueKey(conversation.id),
                            leading: CircleAvatar(
                              child: Text(
                                conversation.nickname.isEmpty
                                    ? '?'
                                    : conversation.nickname.characters.first,
                              ),
                            ),
                            title: Text(
                              conversation.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: LText(
                              '${conversation.lastText.isEmpty ? (conversation.hasAttachment ? '附件' : '暂无消息') : conversation.lastText}\n${conversation.orderId == null ? '咨询' : '订单 · ${conversation.orderId!.substring(28)}'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: conversation.unread == '0'
                                ? const Icon(Icons.chevron_right)
                                : Badge(
                                    label: Text(
                                      BigInt.parse(conversation.unread) >
                                              BigInt.from(99)
                                          ? '99+'
                                          : conversation.unread,
                                    ),
                                  ),
                            onTap: () => room(conversation),
                          ),
                      if (tab == 1 && orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: LText(
                            '暂无 C2C 订单',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (tab == 1)
                        for (final order in orders)
                          ListTile(
                            title: LText(
                              '${asString(order['buyerUserId']) == '${widget.owner}' ? '买入' : '卖出'} ${asString(asMap(order['market'])['asset'])}',
                            ),
                            subtitle: Text(
                              '${asString(order['fiatAmount'])} ${asString(asMap(order['market'])['fiat'])}\n${c2cOrderStatus(asString(order['status']))}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: opening
                                ? null
                                : () => openOrder(asString(order['orderId'])),
                          ),
                      if (more)
                        TextButton(
                          onPressed: loading ? null : () => load(append: true),
                          child: LText(loading ? '加载中…' : '加载更多'),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class C2cChatRoom extends StatefulWidget {
  const C2cChatRoom({
    super.key,
    required this.state,
    required this.owner,
    required this.conversation,
  });
  final AppState state;
  final int owner;
  final C2cConversation conversation;
  @override
  State<C2cChatRoom> createState() => _C2cChatRoomState();
}

class _C2cChatRoomState extends State<C2cChatRoom> with WidgetsBindingObserver {
  final text = TextEditingController(), scroll = ScrollController();
  final storage = const FlutterSecureStorage();
  StreamSubscription<Map<String, dynamic>>? events;
  List<C2cMessage> messages = [];
  List<Map<String, dynamic>> orderEvents = [], reads = [], replies = [];
  Map<String, dynamic>? pending, liveOrder;
  C2cAttachment? attachment;
  PlatformFile? uploadFile;
  Uint8List? uploadBytes;
  String? uploadId, error;
  bool loading = true,
      older = false,
      hasOlder = false,
      sending = false,
      uploading = false,
      orderBusy = false,
      reading = false,
      pendingLoaded = false;
  String after = '0', afterEvent = '0', readMessage = '0', readEvent = '0';
  String requestedReadMessage = '0', requestedReadEvent = '0';
  late bool wasLocked;
  bool get current =>
      mounted && widget.state.session?.user.userId == widget.owner;
  String get id => widget.conversation.id;
  String get pendingKey => 'surprising.c2c.pending.${widget.owner}.$id';
  bool get atBottom => !scroll.hasClients || scroll.offset < 60;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    wasLocked = widget.state.requiresBiometricUnlock;
    widget.state.addListener(unlockChanged);
    events = widget.state.realtime.c2cEvents(widget.owner).listen((event) {
      if (!current) return;
      if (event['op'] == 'c2c.error') {
        setState(() => error = '聊天订阅未完成，请重试');
      } else if (event['op'] == 'c2c.messages') {
        try {
          accept(C2cMessagePage.fromJson(asMap(event['data'])));
        } catch (failure) {
          setState(() => error = clientErrorMessage(failure));
        }
      }
    });
    scroll.addListener(() => unawaited(markRead()));
    unawaited(initialize());
    if (widget.conversation.orderId != null) {
      unawaited(_refreshOrder());
    }
  }

  Future<void> _refreshOrder() async {
    final orderId = widget.conversation.orderId;
    if (orderId == null) return;
    try {
      final value = await widget.state.api.c2cOrder(widget.owner, orderId);
      if (current) setState(() => liveOrder = value);
    } catch (_) {}
  }

  Future<void> _markPaidInChat() async {
    final orderId = widget.conversation.orderId;
    if (orderId == null || orderBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LText('确认已付款'),
        content: const LText('请确认已按订单收款方式完成站外转账，上传付款截图可加速商户核验。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LText('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LText('我已付款'),
          ),
        ],
      ),
    );
    if (ok != true || !current) return;
    setState(() {
      orderBusy = true;
      error = null;
    });
    try {
      await widget.state.api.c2cBusinessPost(
        widget.owner,
        '/orders/$orderId/paid',
        {'proofId': attachment?.id},
      );
      await _refreshOrder();
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => orderBusy = false);
    }
  }

  Future<void> _confirmReleaseInChat() async {
    final orderId = widget.conversation.orderId;
    if (orderId == null || orderBusy) return;
    final emailCtrl = TextEditingController();
    final totpCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LText('确认收款并放币'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LText('务必核对收款账户实际到账后再放币。'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => unawaited(
                widget.state.api.issueSecurityChallenge('WITHDRAWAL'),
              ),
              child: const LText('获取安全验证码'),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: '邮箱验证码'),
            ),
            TextField(
              controller: totpCtrl,
              decoration: const InputDecoration(labelText: '验证器验证码（已绑定时）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LText('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LText('确认放币'),
          ),
        ],
      ),
    );
    final emailCode = emailCtrl.text.trim();
    final totpCode = totpCtrl.text.trim();
    emailCtrl.dispose();
    totpCtrl.dispose();
    if (confirmed != true || !current) return;
    setState(() {
      orderBusy = true;
      error = null;
    });
    try {
      await widget.state.api.c2cBusinessPost(
        widget.owner,
        '/orders/$orderId/release',
        {'emailCode': emailCode, 'totpCode': totpCode},
      );
      await _refreshOrder();
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => orderBusy = false);
    }
  }

  Future<void> initialize() async {
    try {
      final raw = await storage.read(key: pendingKey);
      if (!current) return;
      if (raw != null) {
        final saved = asMap(jsonDecode(raw));
        if (saved['requestId'] is! String || saved['text'] is! String) {
          throw const FormatException('本地待确认消息无法读取');
        }
        setState(() {
          pending = saved;
          text.text = asString(saved['text']);
        });
      }
      pendingLoaded = true;
    } catch (failure) {
      if (current) {
        setState(() => error = clientErrorMessage(failure));
        return;
      }
    }
    unawaited(
      widget.state.api
          .c2cQuickReplies(widget.owner)
          .then((value) {
            if (current) setState(() => replies = value);
          })
          .catchError((Object _) {}),
    );
    await load();
  }

  Future<void> load() async {
    if (current) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final page = await widget.state.api.c2cMessages(
        widget.owner,
        id,
        latest: after == '0',
        after: after == '0' ? null : after,
        afterEvent: after == '0' ? null : afterEvent,
      );
      if (!current) return;
      if (messages.isEmpty) hasOlder = page.hasOlder;
      accept(page);
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  void accept(C2cMessagePage page, {bool history = false}) {
    if (!current || page.conversationId != id) return;
    final pinned = atBottom;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final extent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    setState(() {
      messages = mergeC2cMessages(messages, page.messages);
      orderEvents = {
        for (final event in [...orderEvents, ...page.events])
          c2cId(event['eventId']): event,
      }.values.toList();
      final latest = {for (final read in reads) asString(read['userId']): read};
      for (final read in page.reads) {
        final old = latest[asString(read['userId'])];
        if (old == null ||
            BigInt.parse(c2cId(read['revision'])) >=
                BigInt.parse(c2cId(old['revision']))) {
          latest[asString(read['userId'])] = read;
        }
      }
      reads = latest.values.toList();
      after = c2cMaximum([after, ...page.messages.map((m) => m.id)]);
      afterEvent = c2cMaximum([
        afterEvent,
        ...page.events.map((e) => c2cId(e['eventId'])),
      ]);
    });
    widget.state.realtime.watchC2c(
      owner: widget.owner,
      conversationId: id,
      after: after,
      afterEvent: afterEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current || !scroll.hasClients) return;
      if (pinned) {
        scroll.jumpTo(0);
      } else if (!history) {
        scroll.jumpTo(
          (offset + scroll.position.maxScrollExtent - extent).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
      unawaited(markRead());
    });
  }

  Future<void> earlier() async {
    if (older || messages.isEmpty) return;
    setState(() => older = true);
    try {
      final page = await widget.state.api.c2cMessages(
        widget.owner,
        id,
        before: messages.first.id,
      );
      if (current) {
        accept(page, history: true);
        setState(() => hasOlder = page.hasOlder);
      }
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => older = false);
    }
  }

  Future<void> markRead() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!current ||
        !atBottom ||
        widget.state.requiresBiometricUnlock ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        (ModalRoute.of(context)?.isCurrent == false) ||
        (after == readMessage && afterEvent == readEvent)) {
      return;
    }
    requestedReadMessage = after;
    requestedReadEvent = afterEvent;
    if (reading) return;
    reading = true;
    try {
      while (current &&
          (requestedReadMessage != readMessage ||
              requestedReadEvent != readEvent)) {
        final message = requestedReadMessage, event = requestedReadEvent;
        await widget.state.api.c2cRead(widget.owner, id, message, event);
        readMessage = message;
        readEvent = event;
      }
    } catch (_) {
      /* Retry the same read watermark on the next visible update. */
    } finally {
      reading = false;
    }
  }

  void unlockChanged() {
    final locked = widget.state.requiresBiometricUnlock;
    if (wasLocked && !locked) scheduleRead();
    wasLocked = locked;
  }

  void scheduleRead() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current) unawaited(markRead());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRead();
  }

  Future<void> send() async {
    if (sending ||
        uploading ||
        uploadId != null ||
        !pendingLoaded ||
        (!current)) {
      return;
    }
    if (pending == null && text.text.trim().isEmpty && attachment == null) {
      return;
    }
    final retry = pending != null;
    final original =
        pending ??
        {
          'requestId': c2cUuid(),
          'text': text.text.trim(),
          'attachmentId': attachment?.id,
        };
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await storage.write(key: pendingKey, value: jsonEncode(original));
      if (!current) return;
      setState(() => pending = original);
      C2cMessage? sent;
      if (retry) {
        sent = (await widget.state.api.c2cReceipt(
          widget.owner,
          id,
          asString(original['requestId']),
        )).message;
      }
      sent ??= await widget.state.api.c2cSend(widget.owner, id, original);
      await storage.delete(key: pendingKey);
      if (!current) return;
      setState(() {
        messages = mergeC2cMessages(messages, [sent!]);
        pending = null;
        attachment = null;
        text.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(0);
      });
    } catch (failure) {
      if (!current) return;
      if (!retry &&
          failure is ApiException &&
          [400, 403, 404, 409, 413, 415, 422].contains(failure.statusCode)) {
        await storage.delete(key: pendingKey);
        if (current) setState(() => pending = null);
      }
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => sending = false);
    }
  }

  Future<void> attach({bool retry = false}) async {
    if (uploading || sending || pending != null) return;
    if (!retry) {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (!current || file == null) return;
      final bytes = await file.readAsBytes();
      if (!current) return;
      if (bytes.isEmpty || bytes.length > 10485760) {
        setState(() => error = '请选择 10 MB 以内的 JPG、PNG 或 PDF');
        return;
      }
      uploadFile = file;
      uploadBytes = bytes;
      uploadId = c2cUuid();
    }
    final file = uploadFile, bytes = uploadBytes, originalId = uploadId;
    if (file == null || bytes == null || originalId == null) return;
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      C2cAttachment? ready;
      if (retry) {
        final receipt = await widget.state.api.c2cUploadReceipt(
          widget.owner,
          originalId,
        );
        if (receipt['status'] == 'READY') {
          ready = C2cAttachment.fromJson(receipt);
        }
      }
      ready ??= await widget.state.api.c2cUpload(
        widget.owner,
        widget.conversation,
        originalId,
        file.name,
        file.extension?.toLowerCase() == 'pdf'
            ? 'application/pdf'
            : file.extension?.toLowerCase() == 'png'
            ? 'image/png'
            : 'image/jpeg',
        bytes,
      );
      if (current) {
        setState(() {
          attachment = ready;
          uploadId = null;
          uploadFile = null;
          uploadBytes = null;
        });
      }
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => uploading = false);
    }
  }

  Future<void> order() async {
    final orderId = widget.conversation.orderId;
    if (orderId == null) return;
    try {
      final value = await widget.state.api.c2cOrder(widget.owner, orderId);
      if (!mounted || !current) return;
      final market = asMap(value['market']);
      await showDialog<void>(
        context: context,
        builder: (dialog) =>
            AppScope.of(dialog).session?.user.userId != widget.owner
            ? const AlertDialog(content: LText('登录账户已变化，请关闭订单详情'))
            : AlertDialog(
                title: const LText('订单详情'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(orderId),
                      const SizedBox(height: 16),
                      LText(c2cOrderStatus(asString(value['status']))),
                      LText(
                        '金额：${asString(value['fiatAmount'])} ${asString(market['fiat'])}',
                      ),
                      LText(
                        '数量：${asString(value['quantity'])} ${asString(market['asset'])}',
                      ),
                      LText(
                        '价格：${asString(value['price'])} ${asString(market['fiat'])}',
                      ),
                      if (asString(value['terms']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(asString(value['terms'])),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('关闭'),
                  ),
                ],
              ),
      );
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(unlockChanged);
    unawaited(events?.cancel());
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  Widget _buildChatOrderBar() {
    final row = liveOrder;
    if (row == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: LText(
          '订单 ${widget.conversation.orderId}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
    }
    final status = asString(row['status']);
    final m = asMap(row['market']);
    final payment = asMap(row['payment']);
    final isBuyer = '${row['buyerUserId']}' == '${widget.owner}';
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: colors.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LText(
                  '${c2cOrderStatus(status)} · ${row['fiatAmount']} ${m['fiat']} (${row['quantity']} ${m['asset']})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: orderBusy ? null : _refreshOrder,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (payment.isNotEmpty)
            Text(
              '收款方式：${payment['methodCode'] ?? ''} ${payment['holderName'] ?? ''} ${payment['accountNumber'] ?? ''}',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
          if (status == 'PAYMENT_PENDING' && isBuyer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton.tonal(
                onPressed: orderBusy ? null : _markPaidInChat,
                child: const LText('我已付款，通知卖家'),
              ),
            ),
          if (status == 'PAID' && !isBuyer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                onPressed: orderBusy ? null : _confirmReleaseInChat,
                child: const LText('确认收款并放币'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).session?.user.userId != widget.owner) {
      return const Scaffold(body: Center(child: LText('登录账户已变化，请返回会话列表')));
    }
    final timeline = c2cTimeline(messages, orderEvents);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.conversation.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'UID ${widget.conversation.peerId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (widget.conversation.orderId != null)
            TextButton(onPressed: order, child: const LText('查看订单')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.conversation.orderId != null)
              _buildChatOrderBar(),
            if (error != null)
              MaterialBanner(
                content: LText(
                  error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  TextButton(
                    onPressed: pendingLoaded ? load : initialize,
                    child: const LText('重试'),
                  ),
                ],
              ),
            Expanded(
              child: loading && messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: timeline.length + (hasOlder ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == timeline.length) {
                          return Center(
                            child: TextButton(
                              onPressed: older ? null : earlier,
                              child: LText(older ? '加载中…' : '更早的消息'),
                            ),
                          );
                        }
                        final item = timeline[timeline.length - 1 - index],
                            message = item.message;
                        if (message == null) {
                          final type = asString(item.event!['type']);
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: LText(
                                type == 'BUYER_MARKED_PAID'
                                    ? '买方已标记付款，请另行核实实际到账。'
                                    : type == 'ORDER_CREATED'
                                    ? '订单已创建'
                                    : '订单状态已更新',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontSize: 11),
                              ),
                            ),
                          );
                        }
                        final own =
                            message.sender == '${widget.owner}' &&
                            message.authorKind == 'USER';
                        final read = reads.any(
                          (r) =>
                              asString(r['userId']) ==
                                  widget.conversation.peerId &&
                              BigInt.parse(c2cId(r['messageId'])) >=
                                  BigInt.parse(message.id),
                        );
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final peerInitial = widget.conversation.nickname
                            .trim()
                            .isEmpty
                            ? 'U'
                            : widget.conversation.nickname
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase();
                        final avatar = CircleAvatar(
                          radius: 18,
                          backgroundColor: own
                              ? const Color(0xFF00C6FF).withValues(alpha: 0.20)
                              : const Color(0xFF7B4397).withValues(alpha: 0.22),
                          child: Text(
                            own
                                ? (message.authorKind == 'USER' ? '我' : 'S')
                                : peerInitial,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: own
                                  ? const Color(0xFF00C6FF)
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        );
                        final bubble = CustomPaint(
                          painter: _SocialBubblePainter(
                            isMe: own,
                            isDark: isDark,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              own ? 12 : 19,
                              9,
                              own ? 19 : 12,
                              9,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message.text.isNotEmpty)
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.38,
                                      color: own || isDark
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    ),
                                  ),
                                if (message.attachment != null)
                                  _Attachment(
                                    state: widget.state,
                                    owner: widget.owner,
                                    attachment: message.attachment!,
                                  ),
                              ],
                            ),
                          ),
                        );
                        return Padding(
                          key: ValueKey(message.id),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: own
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!own) ...[avatar, const SizedBox(width: 6)],
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * .72,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: own
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (message.authorKind != 'USER')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 3,
                                          ),
                                          child: LText(
                                            message.authorKind == 'SUPPORT'
                                                ? '平台客服'
                                                : '系统',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                      bubble,
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: 4,
                                          left: own ? 0 : 8,
                                          right: own ? 8 : 0,
                                        ),
                                        child: LText(
                                          '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}${own ? (read ? ' · 已读' : ' · 已发送') : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(fontSize: 10.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (own) ...[const SizedBox(width: 6), avatar],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (pending != null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: LText('发送结果待确认，重试会先查询原消息。'),
              ),
            if (attachment != null || uploadFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    Expanded(
                      child: Text(
                        attachment?.name ?? uploadFile!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (uploadId != null)
                      TextButton(
                        onPressed: uploading ? null : () => attach(retry: true),
                        child: LText(uploading ? '上传中…' : '重试上传'),
                      ),
                    IconButton(
                      onPressed: uploading || pending != null
                          ? null
                          : () => setState(() {
                              attachment = null;
                              uploadFile = null;
                              uploadId = null;
                            }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              decoration: BoxDecoration(
                color: context.tokens.bgElevated1,
                border: Border(
                  top: BorderSide(
                    color: context.tokens.borderDefault.withValues(alpha: 0.6),
                    width: 0.6,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: pending != null || sending || uploading
                        ? null
                        : attach,
                    style: IconButton.styleFrom(
                      backgroundColor: context.tokens.bgElevated2,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(Icons.add, size: 22),
                    tooltip: clientLabel(context, '添加附件'),
                  ),
                  if (replies.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: clientLabel(context, '快捷回复'),
                      enabled: pending == null,
                      onSelected: (value) => text.text = value,
                      itemBuilder: (_) => [
                        for (final reply in replies)
                          PopupMenuItem(
                            value: asString(reply['text']),
                            child: Text(asString(reply['text'])),
                          ),
                      ],
                      icon: const Icon(Icons.quickreply_outlined),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: text,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 4,
                      enabled: pendingLoaded && pending == null && !sending,
                      decoration: InputDecoration(
                        hintText: clientLabel(context, '输入消息…'),
                        counterText: '',
                        filled: true,
                        fillColor: context.tokens.bgElevated2,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: context.tokens.borderDefault.withValues(
                              alpha: 0.5,
                            ),
                            width: 0.6,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: context.tokens.borderDefault.withValues(
                              alpha: 0.5,
                            ),
                            width: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const StadiumBorder(),
                      ),
                      onPressed:
                          sending ||
                              uploading ||
                              uploadId != null ||
                              !pendingLoaded
                          ? null
                          : send,
                      child: LText(
                        sending
                            ? '发送中…'
                            : pending != null
                            ? '查询重试'
                            : '发送',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: LText('聊天消息不代表已付款或已到账。', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attachment extends StatefulWidget {
  const _Attachment({
    required this.state,
    required this.owner,
    required this.attachment,
  });
  final AppState state;
  final int owner;
  final C2cAttachment attachment;
  @override
  State<_Attachment> createState() => _AttachmentState();
}

class _AttachmentState extends State<_Attachment> {
  Future<Uint8List>? bytes;
  bool saving = false;
  String? error;
  bool get current =>
      mounted && widget.state.session?.user.userId == widget.owner;
  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      bytes = widget.state.api.c2cDownload(widget.owner, widget.attachment.id);
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final content =
          await (bytes ??
              widget.state.api.c2cDownload(widget.owner, widget.attachment.id));
      if (!current) return;
      await FilePicker.saveFile(
        dialogTitle: '保存附件',
        fileName: widget.attachment.name.replaceAll(RegExp(r'[/\\]'), '_'),
        bytes: content,
      );
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).session?.user.userId != widget.owner) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.attachment.isImage)
            FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) => SizedBox(
                height: 160,
                child: snapshot.hasData
                    ? GestureDetector(
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (context) => Scaffold(
                              appBar: AppBar(title: const LText('图片')),
                              body: Builder(
                                builder: (context) =>
                                    AppScope.of(context).session?.user.userId !=
                                        widget.owner
                                    ? const SizedBox.shrink()
                                    : InteractiveViewer(
                                        child: Center(
                                          child: Image.memory(snapshot.data!),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        child: Image.memory(
                          snapshot.data!,
                          width: 240,
                          height: 160,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const LText('图片无法显示'),
                        ),
                      )
                    : snapshot.hasError
                    ? Center(
                        child: TextButton(
                          onPressed: () => setState(
                            () => bytes = widget.state.api.c2cDownload(
                              widget.owner,
                              widget.attachment.id,
                            ),
                          ),
                          child: const LText('重新加载附件'),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          Text(
            widget.attachment.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (error != null) LText(error!),
          TextButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.download, size: 16),
            label: LText(saving ? '保存中…' : '保存附件'),
          ),
        ],
      ),
    );
  }
}

class _SocialBubblePainter extends CustomPainter {
  const _SocialBubblePainter({required this.isMe, required this.isDark});

  final bool isMe;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    const tw = 7.0;
    const th = 6.0;
    final ty = (size.height * 0.5).clamp(r + th, 20.0);
    final path = Path();

    if (!isMe) {
      final bx = tw;
      final ex = size.width;
      path.moveTo(bx + r, 0);
      path.lineTo(ex - r, 0);
      path.quadraticBezierTo(ex, 0, ex, r);
      path.lineTo(ex, size.height - r);
      path.quadraticBezierTo(ex, size.height, ex - r, size.height);
      path.lineTo(bx + r, size.height);
      path.quadraticBezierTo(bx, size.height, bx, size.height - r);
      path.lineTo(bx, ty + th);
      path.lineTo(0, ty);
      path.lineTo(bx, ty - th);
      path.lineTo(bx, r);
      path.quadraticBezierTo(bx, 0, bx + r, 0);
      path.close();
    } else {
      final ex = size.width - tw;
      path.moveTo(r, 0);
      path.lineTo(ex - r, 0);
      path.quadraticBezierTo(ex, 0, ex, r);
      path.lineTo(ex, ty - th);
      path.lineTo(size.width, ty);
      path.lineTo(ex, ty + th);
      path.lineTo(ex, size.height - r);
      path.quadraticBezierTo(ex, size.height, ex - r, size.height);
      path.lineTo(r, size.height);
      path.quadraticBezierTo(0, size.height, 0, size.height - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
      path.close();
    }

    final rect = Offset.zero & size;
    final gradient = isMe
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF1A1D2E), Color(0xFF242040)]
                : const [Color(0xFFF3F4F8), Color(0xFFEBEFF7)],
          );
    final fillPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = isMe
          ? Colors.white.withValues(alpha: 0.18)
          : isDark
          ? const Color(0xFF2F2F43)
          : const Color(0xFFD7DCE6);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SocialBubblePainter oldDelegate) =>
      oldDelegate.isMe != isMe || oldDelegate.isDark != isDark;
}
