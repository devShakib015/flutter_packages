/// Apple Intelligence from Flutter, beyond the language model.
library;

// Explicit `show` clauses rather than wholesale exports, so the public surface
// is a decision. A wholesale export also carries top-level functions, which is
// how `exceptionFor` — the internal platform-code mapper — was public API.

export 'src/availability.dart'
    show ImageGenerationAvailability, ImageGenerationStatus;
export 'src/concept.dart' show ImageConcept, ImageStyle;
export 'src/exceptions.dart'
    show
        AppleIntelligenceException,
        GenerationFailedException,
        GenerationRefusal,
        GenerationRefusedException,
        GenerationUnavailableException,
        OsTooOldException;
export 'src/image_creator.dart' show GeneratedImage, ImageCreator;
export 'src/image_playground_sheet.dart' show ImagePlaygroundSheet;
export 'src/native_text_field.dart'
    show AppleIntelligenceTextField, NativeTextController, TextCapabilities;
