import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'app.dart' show AppScope, AuthSheet, clientText;
import 'app_state.dart';
import 'c2c_models.dart';
import 'models.dart';

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
            const Text('登录后查看 C2C 会话与订单'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AuthSheet(),
              ),
              child: const Text('登录'),
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
          title: const Text('咨询商家'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                maxLength: 19,
                decoration: const InputDecoration(labelText: '商家 UID'),
              ),
              const Text('咨询遵循对方的隐私设置。订单会话请从订单进入。'),
              if (problem != null)
                Text(
                  problem!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('取消'),
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
              child: Text(busy ? '打开中…' : '打开会话'),
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
                child: Text(
                  clientText(language, 'C2C 消息与订单', 'C2C messages & orders'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: enabled ? consult : null,
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: '咨询商家',
              ),
              IconButton(
                onPressed: loading ? null : () => load(),
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
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
                label: Text(clientText(language, '会话', 'Messages')),
              ),
              ButtonSegment(
                value: 1,
                label: Text(clientText(language, '订单', 'Orders')),
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
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索会话',
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
            content: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis),
            actions: [
              TextButton(onPressed: () => load(), child: const Text('重试')),
            ],
          ),
        Expanded(
          child: loading && conversations.isEmpty && orders.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : !enabled
              ? Center(child: Text(error == null ? 'C2C 聊天暂未开启' : '暂时无法加载 C2C'))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (tab == 0 && conversations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
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
                            subtitle: Text(
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
                          child: Text('暂无 C2C 订单', textAlign: TextAlign.center),
                        ),
                      if (tab == 1)
                        for (final order in orders)
                          ListTile(
                            title: Text(
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
                          child: Text(loading ? '加载中…' : '加载更多'),
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
  Map<String, dynamic>? pending;
  C2cAttachment? attachment;
  PlatformFile? uploadFile;
  String? uploadId, error;
  bool loading = true,
      older = false,
      hasOlder = false,
      sending = false,
      uploading = false,
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (!current || result == null) return;
      final file = result.files.single;
      if (file.bytes == null || file.size > 10485760 || file.size == 0) {
        setState(() => error = '请选择 10 MB 以内的 JPG、PNG 或 PDF');
        return;
      }
      uploadFile = file;
      uploadId = c2cUuid();
    }
    final file = uploadFile, originalId = uploadId;
    if (file == null || originalId == null) return;
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
        file.bytes!,
      );
      if (current) {
        setState(() {
          attachment = ready;
          uploadId = null;
          uploadFile = null;
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
            ? const AlertDialog(content: Text('登录账户已变化，请关闭订单详情'))
            : AlertDialog(
                title: const Text('订单详情'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(orderId),
                      const SizedBox(height: 16),
                      Text(c2cOrderStatus(asString(value['status']))),
                      Text(
                        '金额：${asString(value['fiatAmount'])} ${asString(market['fiat'])}',
                      ),
                      Text(
                        '数量：${asString(value['quantity'])} ${asString(market['asset'])}',
                      ),
                      Text(
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
                    child: const Text('关闭'),
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

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).session?.user.userId != widget.owner) {
      return const Scaffold(body: Center(child: Text('登录账户已变化，请返回会话列表')));
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
            TextButton(onPressed: order, child: const Text('查看订单')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.conversation.orderId != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '订单 ${widget.conversation.orderId}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            if (error != null)
              MaterialBanner(
                content: Text(
                  error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  TextButton(
                    onPressed: pendingLoaded ? load : initialize,
                    child: const Text('重试'),
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
                              child: Text(older ? '加载中…' : '更早的消息'),
                            ),
                          );
                        }
                        final item = timeline[timeline.length - 1 - index],
                            message = item.message;
                        if (message == null) {
                          final type = asString(item.event!['type']);
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              type == 'BUYER_MARKED_PAID'
                                  ? '买方已标记付款，请另行核实实际到账。'
                                  : type == 'ORDER_CREATED'
                                  ? '订单已创建'
                                  : '订单状态已更新',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
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
                        return Align(
                          key: ValueKey(message.id),
                          alignment: own
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .82,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: own
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (message.authorKind != 'USER')
                                  Text(
                                    message.authorKind == 'SUPPORT'
                                        ? '平台客服'
                                        : '系统',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: own
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (message.text.isNotEmpty)
                                        Text(message.text),
                                      if (message.attachment != null)
                                        _Attachment(
                                          state: widget.state,
                                          owner: widget.owner,
                                          attachment: message.attachment!,
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}${own ? (read ? ' · 已读' : ' · 已发送') : ''}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (pending != null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('发送结果待确认，重试会先查询原消息。'),
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
                        child: Text(uploading ? '上传中…' : '重试上传'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: pending != null || sending || uploading
                        ? null
                        : attach,
                    icon: const Icon(Icons.attach_file),
                    tooltip: '添加附件',
                  ),
                  if (replies.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: '快捷回复',
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
                  Expanded(
                    child: TextField(
                      controller: text,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 4,
                      enabled: pendingLoaded && pending == null && !sending,
                      decoration: const InputDecoration(
                        hintText: '输入消息…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        sending ||
                            uploading ||
                            uploadId != null ||
                            !pendingLoaded
                        ? null
                        : send,
                    child: Text(
                      sending
                          ? '发送中…'
                          : pending != null
                          ? '查询重试'
                          : '发送',
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text('聊天消息不代表已付款或已到账。', style: TextStyle(fontSize: 11)),
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
      await FilePicker.platform.saveFile(
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
                              appBar: AppBar(title: const Text('图片')),
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
                          errorBuilder: (_, _, _) => const Text('图片无法显示'),
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
                          child: const Text('重新加载附件'),
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
          if (error != null) Text(error!),
          TextButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.download, size: 16),
            label: Text(saving ? '保存中…' : '保存附件'),
          ),
        ],
      ),
    );
  }
}
