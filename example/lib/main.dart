import 'dart:math';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:transparent_image/transparent_image.dart';

MediaControl playControl = MediaControl(
  androidIcon: 'drawable/ic_action_play_arrow',
  label: 'Play',
  action: MediaAction.play,
);
MediaControl pauseControl = MediaControl(
  androidIcon: 'drawable/ic_action_pause',
  label: 'Pause',
  action: MediaAction.pause,
);
MediaControl fastForwardControl = MediaControl(
  androidIcon: 'drawable/ic_action_forward_10',
  label: 'Fast Forward',
  action: MediaAction.fastForward,
);
MediaControl rewindControl = MediaControl(
  androidIcon: 'drawable/ic_action_replay_10',
  label: 'Rewind',
  action: MediaAction.rewind,
);
MediaControl stopControl = MediaControl(
  androidIcon: 'drawable/ic_action_stop',
  label: 'Stop',
  action: MediaAction.stop,
);

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Audio Service Demo',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: new HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: Text('Audio Service Demo'),
      ),
      body: Center(
        child: RaisedButton(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => AudioServiceWidget(child: MainScreen()))),
          child: Text('PLAY'),
        ),
      ),
    );
  }
}
class MainScreen extends StatefulWidget {
  MainScreen();

  @override
  State<StatefulWidget> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Tracks the position while the user drags the seek bar.
  final BehaviorSubject<double> _dragPositionSubject =
  BehaviorSubject.seeded(null);

  bool isReady = false;
  bool isDisposed = false;

  _MainScreenState();

  @override
  void initState() {
    AudioService.start(
      backgroundTaskEntrypoint: audioPlayerTaskEntryPoint,
      androidNotificationChannelName: 'Audio Player',
      // Enable this if you want the Android service to exit the foreground state on pause.
      //androidStopForegroundOnPause: true,
      androidNotificationColor: 0xFF1ED760,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidEnableQueue: true,
      params: audioPlayerTaskGenerateParam(),
      rewindInterval: Duration(seconds: 10),
      fastForwardInterval: Duration(seconds: 10),
    );

    AudioService.customEventStream.listen((event) {
      if (event == 'COMPLETED') {
        if (context != null && !isDisposed) {
          Navigator.of(context).pop();
          isDisposed = true;
        }
      } else if (event == 'PLAYING') {
        isReady = true;
      }
    });
    AudioService.playbackStateStream.listen((event) {
      if(event?.processingState == AudioProcessingState.stopped){
        if (context != null && !isDisposed) {
          Navigator.of(context).pop();
          isDisposed = true;
        }
      }
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return new WillPopScope(
        child: Scaffold(
          appBar: AppBar(
              leading: IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () async {
                    AudioService.stop();
                    //Navigator.of(context).pop();
                  }),
                ),
          body: StreamBuilder<ScreenState>(
            stream: _screenStateStream,
            builder: (context, snapshot) {
              final screenState = snapshot.data;
              final mediaItem = screenState?.mediaItem;
              final state = screenState?.playbackState;
              final processingState =
                  state?.processingState ?? AudioProcessingState.none;
              final playing = state?.playing ?? false;
              return Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                      child: Center(
                          child: Container(
                            width: 250.0,
                            height: 250.0,
                            decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(.5),
                                shape: BoxShape.circle),
                            child: Stack(
                              children: <Widget>[
                                if (processingState != AudioProcessingState.ready)
                                  Center(
                                      child: SizedBox(
                                          height: 240.0,
                                          width: 240.0,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 3.0))),
                                Center(
                                  child: Container(
                                    width: 230.0,
                                    height: 230.0,
                                    child: ClipOval(
                                      clipper: MClipper(),
                                      child: FadeInImage.memoryNetwork(
                                        placeholder: kTransparentImage,
                                        image: 'https://ia601400.us.archive.org/21/items/playerbg38/playerbg27.jpg',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ))),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Text('La Citadelle')),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Text('  ')),
                  SizedBox(
                    height: 16.0,
                  ),
                  positionIndicator(context, mediaItem, state),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 14.0),
                      child: ButtonBar(
                        alignment: MainAxisAlignment.center,
                        children: <Widget>[
                          FlatButton(
                            child: Icon(
                              Icons.replay_10,
                              size: 42,
                              color: Colors.blue,
                            ),
                            onPressed: (isReady) ? AudioService.rewind : null,
                          ),
                          if (playing)
                            pauseButton(processingState)
                          else
                            playButton(processingState),
                          FlatButton(
                            child: Icon(
                              Icons.forward_10,
                              size: 42,
                              color: Colors.blue,
                            ),
                            onPressed:
                            (isReady) ? AudioService.fastForward : null,
                          ),
                        ],
                      )),
                ],
              );
            },
          ),
        ),
        onWillPop: () async {
          await AudioService.stop();
          return false;
        });
  }

  /// Encapsulate all the different data we're interested in into a single
  /// stream so we don't have to nest StreamBuilders.
  Stream<ScreenState> get _screenStateStream =>
      Rx.combineLatest3<List<MediaItem>, MediaItem, PlaybackState, ScreenState>(
          AudioService.queueStream,
          AudioService.currentMediaItemStream,
          AudioService.playbackStateStream,
              (queue, mediaItem, playbackState) =>
              ScreenState(queue, mediaItem, playbackState));

  FlatButton playButton(AudioProcessingState processingState) => FlatButton(
    child: Icon(
      Icons.play_circle_outline,
      size: 78,
      color: Colors.blue,
    ),
    onPressed: (isReady) ? AudioService.play : null,
  );

  FlatButton pauseButton(AudioProcessingState processingState) => FlatButton(
    child: Icon(
      Icons.pause,
      size: 78,
      color: Colors.blue,
    ),
    onPressed: (isReady) ? AudioService.pause : null,
  );

  Widget positionIndicator(
      BuildContext context, MediaItem mediaItem, PlaybackState state) {
    if (!isReady) {
      return _disabledSeekbar();
    }
    double seekPos;
    var startAt = 0;
    return StreamBuilder(
      stream: Rx.combineLatest2<double, double, double>(
          _dragPositionSubject.stream,
          Stream.periodic(Duration(milliseconds: 200)),
              (dragPosition, _) => dragPosition),
      builder: (context, snapshot) {
        double audioPosition = state?.currentPosition?.inSeconds?.toDouble();
        double position = snapshot.data ??
            (audioPosition != null ? audioPosition - startAt : 0);
        double duration = mediaItem?.duration?.inSeconds?.toDouble();
        if (duration != null && (seekPos != null || position >= 0)) {
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.grey[600],
                  thumbColor: Colors.blue,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.0),
                ),
                child: Slider(
                  min: 0.0,
                  max: duration,
                  value: seekPos ?? max(0.0, min(position, duration)),
                  onChanged: (value) {
                    _dragPositionSubject.add(value);
                  },
                  onChangeEnd: (value) {
                    AudioService.seekTo(
                        Duration(seconds: value.toInt() + startAt));
                    // Due to a delay in platform channel communication, there is
                    // a brief moment after releasing the Slider thumb before the
                    // new position is broadcast from the platform side. This
                    // hack is to hold onto seekPos until the next state update
                    // comes through.
                    // TODO: Improve this code.
                    seekPos = value;
                    _dragPositionSubject.add(null);
                  },
                ),
              ),
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
                child: Row(
                  children: <Widget>[
                    Text('${position.toInt()}'),
                    Expanded(
                      child: Text(''),
                    ),
                    Text('${mediaItem.duration.inSeconds}'),
                  ],
                ),
              ),
            ],
          );
        } else
          return _disabledSeekbar();
      },
    );
  }

  Widget _disabledSeekbar() {
    return Column(
      children: [
        SliderTheme(
          //https://miro.medium.com/max/1400/1*e5xMmR_9Vku4Dya9HbXD2Q.png
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey[600],
            thumbColor: Colors.blue,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.0),
          ),
          child: Slider(
            min: 0.0,
            max: 1,
            value: 0,
            onChanged: null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
          child: Row(
            children: <Widget>[
              Text('--:--'),
              Expanded(
                child: Text(''),
              ),
              Text('--:--'),
            ],
          ),
        ),
      ],
    );
  }
}

class ScreenState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;
  final PlaybackState playbackState;

  ScreenState(this.queue, this.mediaItem, this.playbackState);
}

// NOTE: Your entry point MUST be a top-level function.
void audioPlayerTaskEntryPoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

Map<String, dynamic> audioPlayerTaskGenerateParam() {
  var map = {
    'id': 'https://freepd.com/music/La%20Citadelle.mp3',
    'album': 'Concentration',
    'title': 'La Citadelle',
    'artist': '',
    'duration': 162,
    'art_uri': 'https://ia601400.us.archive.org/21/items/playerbg38/playerbg27.jpg',
    'start_at': 0,
    'end_at': 162,
    'resume_at': 0,
  };
  //print('audio param: $map');
  return map;
}

MediaItem generateFromParam(Map<String, dynamic> param) {
  return MediaItem(
      id: param['id'],
      album: param['album'],
      title: param['title'],
      artist: param['artist'],
      duration: Duration(seconds: param['duration']),
      artUri: param['art_uri'],
      extras: {
        'start_at': param['start_at'],
        'end_at': param['end_at'],
        'resume_at': param['resume_at']
      });
}

class AudioPlayerTask extends BackgroundAudioTask {
  List<MediaItem> _queue = [];
  int _queueIndex = -1;
  AudioPlayer _audioPlayer = new AudioPlayer();
  AudioProcessingState _skipState;
  bool _playing;
  bool _interrupted = false;

  bool get hasNext => _queueIndex + 1 < _queue.length;

  bool get hasPrevious => _queueIndex > 0;

  MediaItem get mediaItem => _queue[_queueIndex];

  StreamSubscription<AudioPlaybackState> _playerStateSubscription;
  StreamSubscription<AudioPlaybackState> _tempplayerStateSubscription;
  StreamSubscription<AudioPlaybackEvent> _eventSubscription;

  Duration get startAt => Duration(seconds: mediaItem.extras['start_at']);

  Duration get endAt {
    if (mediaItem.extras['end_at'] != -1)
      return Duration(seconds: mediaItem.extras['end_at']);
    return mediaItem.duration;
  }

  Duration get resumeAt => Duration(seconds: mediaItem.extras['resume_at']);

  @override
  void onStart(Map<String, dynamic> params) {
//    print('AudioPlayerTask>> onStart $params');
    _queue = [generateFromParam(params)];
    _playerStateSubscription = _audioPlayer.playbackStateStream
        .where((state) => state == AudioPlaybackState.completed)
        .listen((state) {
      _handlePlaybackCompleted();
    });
    _tempplayerStateSubscription = _audioPlayer.playbackStateStream
        .listen((state) {
//      print('AudioPlayerTask>> just audio state>> $state');
      if(state == AudioPlaybackState.playing){
        AudioServiceBackground.sendCustomEvent('PLAYING');
      }
    });
    _audioPlayer.getPositionStream().listen((position) {
      if (position >= endAt) {
        onStop();
      }
    });
    _eventSubscription = _audioPlayer.playbackEventStream.listen((event) {
      final bufferingState =
      event.buffering ? AudioProcessingState.buffering : null;
      switch (event.state) {
        case AudioPlaybackState.paused:
          _setState(
            processingState: bufferingState ?? AudioProcessingState.ready,
            position: event.position,
          );
          break;
        case AudioPlaybackState.playing:
          _setState(
            processingState: bufferingState ?? AudioProcessingState.ready,
            position: event.position,
          );
          break;
        case AudioPlaybackState.connecting:
          _setState(
            processingState: _skipState ?? AudioProcessingState.connecting,
            position: event.position,
          );
          break;
        default:
          break;
      }
    });

    AudioServiceBackground.setQueue(_queue);
    onSkipToNext();
  }

  void _handlePlaybackCompleted() {
//    print('AudioPlayerTask>> _handlePlaybackCompleted');
    if (hasNext) {
      onSkipToNext();
    } else {
      onStop();
    }
  }

  void playPause() {
//    print('AudioPlayerTask>> playPause');
    if (AudioServiceBackground.state.playing)
      onPause();
    else
      onPlay();
  }

  @override
  Future<void> onSkipToNext() => _skip(1);

  @override
  Future<void> onSkipToPrevious() => _skip(-1);

  Future<void> _skip(int offset) async {
//    print('AudioPlayerTask>> _skip >> offset: $offset playing? $_playing');
    final newPos = _queueIndex + offset;
    if (!(newPos >= 0 && newPos < _queue.length)) return;
    if (_playing == null) {
      // First time, we want to start playing
      _playing = true;
    } else if (_playing) {
      // Stop current item
      await _audioPlayer.stop();
    }
    // Load next item
    _queueIndex = newPos;
    AudioServiceBackground.setMediaItem(mediaItem);
    _skipState = offset > 0
        ? AudioProcessingState.skippingToNext
        : AudioProcessingState.skippingToPrevious;
    await _audioPlayer.setUrl(mediaItem.id);
    _skipState = null;
    // Resume playback if we were playing
    if (_playing) {
//      print('AudioPlayerTask>> _skip >> resume from ${resumeAt.inSeconds}');
      await _audioPlayer.seek(resumeAt);
      onPlay();
    } else {
      _setState(processingState: AudioProcessingState.ready);
    }
  }

  @override
  void onPlay(){
//    print('AudioPlayerTask>> onPlay');
    if (_skipState == null) {
      _playing = true;
      _audioPlayer.play();
      //AudioServiceBackground.sendCustomEvent('just played');
    }
  }

  @override
  void onPause() {
//    print('AudioPlayerTask>> onPause');
    if (_skipState == null) {
      _playing = false;
      _audioPlayer.pause();
      //AudioServiceBackground.sendCustomEvent('just paused');
    }
  }

  @override
  void onSeekTo(Duration position) {
//    print('AudioPlayerTask>> onSeekTo ${position.inSeconds} seconds');
    if (position < startAt) position = startAt;
    if (position > endAt) position = endAt;
    _audioPlayer.seek(position);
  }

  @override
  void onClick(MediaButton button) {
    playPause();
  }

  @override
  Future<void> onFastForward() async {
    await _seekRelative(fastForwardInterval);
  }

  @override
  Future<void> onRewind() async {
    await _seekRelative(-rewindInterval);
  }

  Future<void> _seekRelative(Duration offset) async {
//    print('AudioPlayerTask>> _seekRelative ${offset.inSeconds} seconds');
    var newPosition = _audioPlayer.playbackEvent.position + offset;
    if (newPosition < startAt) newPosition = startAt;
    if (newPosition > endAt) newPosition = endAt;
    await _audioPlayer.seek(newPosition);
  }

  @override
  Future<void> onStop() async {
//    print('AudioPlayerTask>> onStop');
    try {
      await _audioPlayer.pause();
    } catch (err) {
//      print('ignore error: $err');
    }
//    print('AudioPlayerTask>> onStop >> paused');
    try{
      await _audioPlayer.stop();
    } catch (err) {
//      print('ignore error: $err');
    }
//    print('AudioPlayerTask>> onStop >> stopped');
    await _audioPlayer.dispose();
//    print('AudioPlayerTask>> onStop >> disposed');
    _playing = false;
    _playerStateSubscription.cancel();
    _tempplayerStateSubscription.cancel();
    _eventSubscription.cancel();
    await _setState(processingState: AudioProcessingState.stopped);
//    print('AudioPlayerTask>> onStop >> set state stopped');
    // Shut down this task
    await super.onStop();
//    print('AudioPlayerTask>> onStop >> super stopped');
    AudioServiceBackground.sendCustomEvent('COMPLETED');
  }

  /* Handling Audio Focus */
  @override
  void onAudioFocusLost(AudioInterruption interruption) {
    if (_playing) _interrupted = true;
    switch (interruption) {
      case AudioInterruption.pause:
      case AudioInterruption.temporaryPause:
      case AudioInterruption.unknownPause:
        onPause();
        break;
      case AudioInterruption.temporaryDuck:
        _audioPlayer.setVolume(0.5);
        break;
    }
  }

  @override
  void onAudioFocusGained(AudioInterruption interruption) {
    switch (interruption) {
      case AudioInterruption.temporaryPause:
        if (!_playing && _interrupted) onPlay();
        break;
      case AudioInterruption.temporaryDuck:
        _audioPlayer.setVolume(1.0);
        break;
      default:
        break;
    }
    _interrupted = false;
  }

  @override
  void onAudioBecomingNoisy() {
    onPause();
  }

  Future<void> _setState({
    AudioProcessingState processingState,
    Duration position,
    Duration bufferedPosition,
  }) async {
    if (position == null) {
      position = _audioPlayer.playbackEvent.position;
    }
    await AudioServiceBackground.setState(
      controls: getControls(),
      systemActions: [MediaAction.seekTo],
      processingState:
      processingState ?? AudioServiceBackground.state.processingState,
      playing: _playing,
      position: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: _audioPlayer.speed,
    );
  }

  List<MediaControl> getControls() {
    if (_playing) {
      return [rewindControl, pauseControl, stopControl, fastForwardControl];
    } else {
      return [rewindControl, playControl, stopControl, fastForwardControl];
    }
  }

  @override
  void onTaskRemoved() {
    print('App is removed from recent apps');
    onStop();
  }
}

/// An object that performs interruptable sleep.
class Sleeper {
  Completer _blockingCompleter;

  /// Sleep for a duration. If sleep is interrupted, a
  /// [SleeperInterruptedException] will be thrown.
  Future<void> sleep([Duration duration]) async {
    _blockingCompleter = Completer();
    if (duration != null) {
      await Future.any([Future.delayed(duration), _blockingCompleter.future]);
    } else {
      await _blockingCompleter.future;
    }
    final interrupted = _blockingCompleter.isCompleted;
    _blockingCompleter = null;
    if (interrupted) {
      throw SleeperInterruptedException();
    }
  }

  /// Interrupt any sleep that's underway.
  void interrupt() {
    if (_blockingCompleter?.isCompleted == false) {
      _blockingCompleter.complete();
    }
  }
}

class SleeperInterruptedException {}

class MClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    return Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: min(size.width, size.height) / 2);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}
