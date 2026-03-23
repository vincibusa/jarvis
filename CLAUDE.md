# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jarvis is an on-device iOS AI assistant (iPhone only, iOS 17+) built with SwiftUI. It runs a quantized LLM locally via MLX Swift — no cloud API calls. The app speaks Italian by default and includes voice input/output, tool calling, and persistent memory.

**LLM**: `mlx-community/Qwen3.5-2B-OptiQ-4bit` (~1.4 GB, downloaded on first launch to HuggingFace cache)

## Build & Run

The project uses Xcode with Swift Package Manager. Project configuration is in `project.yml` (XcodeGen format) and `Jarvis.xcodeproj`.

```bash
# Open in Xcode
open Jarvis.xcodeproj

# Build from command line
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -destination 'platform=iOS,name=<DEVICE_NAME>' build

# Generate/regenerate Xcode project from project.yml (requires xcodegen)
xcodegen generate
```

Must build on a **physical iPhone** — the simulator lacks microphone access and MLX GPU acceleration. Set `DEVELOPMENT_TEAM` in project.yml or Xcode signing settings.

No test target exists yet.

## Architecture

### Data Flow

```
ContentView (root)
  ├─ ModelDownloadView (shown while model downloads/loads)
  └─ ChatView (shown when model is .ready or .generating)
       ├─ LLMService — loads model, streams responses, filters <think> blocks
       ├─ ToolRouter — dispatches tool calls from LLM to native tools
       ├─ SpeechService — STT (on-device, it-IT) + TTS (AVSpeechSynthesizer)
       └─ MemoryService — SwiftData CRUD for conversations, messages, facts
```

### Key Wiring

1. `JarvisApp` creates the `LLMService` (as `@Observable` via `@State`) and the SwiftData `ModelContainer` (schema: `Conversation`, `Message`, `MemoryFact`)
2. `ContentView.configureTools()` creates `MemoryService` → `ToolRouter` → injects into `LLMService` once model is `.ready`
3. `LLMService.createSession()` builds a `ChatSession` (from MLXLMCommon) with tool specs and a `toolDispatch` closure that calls `ToolRouter.execute()`
4. `LLMService.send()` returns `AsyncThrowingStream<String, Error>` — chunks are filtered to strip `<think>...</think>` reasoning blocks before yielding
5. `ChatView.sendMessage()` appends user+assistant Messages, iterates the stream to fill assistant content, then speaks the result via `SpeechService`

### Tool System

Tools are defined in `ToolDefinition.swift` as `ToolSpec` dictionaries (OpenAI function-calling format). `ToolRouter` maps `JarvisToolName` enum cases to concrete tool implementations:

| Tool | Implementation | Framework |
|------|---------------|-----------|
| `get_current_datetime` | `TimeTool` (static) | Foundation |
| `get_events` / `create_event` | `CalendarTool` | EventKit |
| `get_reminders` / `create_reminder` | `ReminderTool` | EventKit |
| `get_current_location` | `LocationTool` | CoreLocation |
| `analyze_image` | `ImageTool` → `VisionService` | Vision (stub — UI picker not wired) |
| `remember` / `recall` | `MemoryTool` → `MemoryService` | SwiftData |

**To add a new tool**: add a case to `JarvisToolName`, create a `ToolSpec` in `ToolDefinitions.allToolSpecs`, implement the tool class, add dispatch in `ToolRouter.execute()`.

### Concurrency Model

- `LLMService`, `ToolRouter`, `MemoryTool` are `@MainActor`
- `ToolRouter` is `@unchecked Sendable` so it can be captured in `ChatSession`'s `@Sendable` toolDispatch closure
- `SWIFT_STRICT_CONCURRENCY: complete` is enabled project-wide

### Persistence

SwiftData with three `@Model` classes:
- `Conversation` — has `@Relationship(deleteRule: .cascade)` to `[Message]`
- `Message` — role stored as `String` (mapped via `MessageRole` enum), optional `toolName`/`toolArgs`
- `MemoryFact` — key-value pairs injected into the system prompt on session start

### UI

- Dark-only (`preferredColorScheme(.dark)`)
- Theme tokens in `JarvisTheme` (colors as hex, fonts, spacing)
- Voice input: hold-to-talk via `VoiceButton` with `DragGesture`
- All UI text is in Italian

### Dependencies

Single external dependency: `mlx-swift-lm` (branch: main) from `ml-explore/mlx-swift-lm`, providing `MLXLLM` and `MLXLMCommon` products. Pulled via SPM.

### System Prompt

Built by `LLMService.buildSystemPrompt()` — includes current date in Italian and any stored `MemoryFact` entries. Instructs the model to use tools rather than guess real-time info.
