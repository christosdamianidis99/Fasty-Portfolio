import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.languageCode);

  final String languageCode;

  bool get isGreek => languageCode == 'el';

  static AppStrings of(BuildContext context) {
    return AppStrings(Localizations.localeOf(context).languageCode);
  }

  String pick(String english, String greek) => isGreek ? greek : english;

  String get appName => 'Fasty';
  String get workspace => pick('Workspace', 'Χώρος εργασίας');
  String get workspaces => pick('Workspaces', 'Χώροι εργασίας');
  String get trash => pick('Trash', 'Κάδος');
  String get activity => pick('Activity', 'Δραστηριότητα');
  String get settings => pick('Settings', 'Ρυθμίσεις');
  String get appearance => pick('Appearance', 'Εμφάνιση');
  String get theme => pick('Theme', 'Θέμα');
  String get systemTheme => pick('System', 'Σύστημα');
  String get lightTheme => pick('Light', 'Φωτεινό');
  String get darkTheme => pick('Dark', 'Σκοτεινό');
  String get accentColor => pick('Accent color', 'Χρώμα έμφασης');
  String get language => pick('Language', 'Γλώσσα');
  String get english => pick('English', 'Αγγλικά');
  String get greek => pick('Greek', 'Ελληνικά');
  String get close => pick('Close', 'Κλείσιμο');
  String get cancel => pick('Cancel', 'Ακύρωση');
  String get save => pick('Save', 'Αποθήκευση');
  String get create => pick('Create', 'Δημιουργία');
  String get done => pick('Done', 'Τέλος');
  String get retry => pick('Retry', 'Επανάληψη');
  String get queued => pick('Queued', 'Σε αναμονή');
  String get note => pick('Note', 'Σημείωση');
  String get notes => pick('Notes', 'Σημειώσεις');
  String get synced => pick('Synced', 'Συγχρονισμένο');
  String get pending => pick('Pending', 'Εκκρεμεί');
  String get unknownNote => pick('Unknown note', 'Άγνωστη σημείωση');

  String get syncDetails => pick('Sync details', 'Λεπτομέρειες συγχρονισμού');
  String get syncNow => pick('Sync now', 'Συγχρονισμός τώρα');
  String get synchronizeTooltip => pick(
    'Synchronize notes and workspaces',
    'Συγχρονισμός σημειώσεων και χώρων εργασίας',
  );
  String get syncing => pick('Synchronizing…', 'Γίνεται συγχρονισμός…');
  String get syncingDescription => pick(
    'Synchronizing local and server changes.',
    'Συγχρονίζονται οι τοπικές αλλαγές με τον διακομιστή.',
  );
  String get synchronized => pick('Synchronized', 'Συγχρονισμένο');
  String get unavailable =>
      pick('Sync unavailable', 'Ο συγχρονισμός δεν είναι διαθέσιμος');
  String get failed => pick('Sync failed', 'Αποτυχία συγχρονισμού');
  String get pendingChanges => pick('Pending changes', 'Εκκρεμείς αλλαγές');
  String get noPendingChanges =>
      pick('No pending changes.', 'Δεν υπάρχουν εκκρεμείς αλλαγές.');
  String get noPendingNoteOperations => pick(
    'No pending note operations',
    'Δεν υπάρχουν εκκρεμείς ενέργειες σημειώσεων',
  );
  String get localChangesSafe => pick(
    'Your changes remain safe on this device and will be retried.',
    'Οι αλλαγές παραμένουν ασφαλείς σε αυτή τη συσκευή και θα δοκιμαστούν ξανά.',
  );
  String get serverUnavailable => pick(
    'The sync server cannot be reached. Your local changes are safe and will be retried automatically.',
    'Δεν είναι δυνατή η σύνδεση με τον διακομιστή συγχρονισμού. Οι τοπικές αλλαγές είναι ασφαλείς και θα δοκιμαστούν ξανά αυτόματα.',
  );
  String get workspaceChanges => pick(
    'Workspace layout, membership, camera, or connections',
    'Διάταξη, περιεχόμενο, προβολή ή συνδέσεις χώρου εργασίας',
  );
  String get createdNote => pick('New note', 'Νέα σημείωση');
  String get editedNote => pick('Edited note', 'Επεξεργασμένη σημείωση');
  String get deletedNote => pick('Deleted note', 'Διαγραμμένη σημείωση');
  String get lastSyncResult =>
      pick('Last sync result', 'Τελευταίο αποτέλεσμα συγχρονισμού');
  String get everythingSynchronized =>
      pick('Everything is synchronized', 'Όλα είναι συγχρονισμένα');
  String get syncCheckComplete => pick(
    'Sync check completed. Everything is up to date.',
    'Ο έλεγχος συγχρονισμού ολοκληρώθηκε. Όλα είναι ενημερωμένα.',
  );
  String get notSyncedYet => pick(
    'No synchronization has run yet.',
    'Δεν έχει πραγματοποιηθεί ακόμη συγχρονισμός.',
  );
  String synchronizedChanges(int count) => pick(
    '$count queued change${count == 1 ? '' : 's'} synchronized successfully.',
    'Συγχρονίστηκ${count == 1 ? 'ε' : 'αν'} επιτυχώς $count εκκρεμ${count == 1 ? 'ής αλλαγή' : 'είς αλλαγές'}.',
  );
  String pendingChangeCount(int count) => pick(
    '$count change${count == 1 ? '' : 's'} pending',
    '$count εκκρεμ${count == 1 ? 'ής αλλαγή' : 'είς αλλαγές'}',
  );

  String get newNote => pick('New note', 'Νέα σημείωση');
  String get editNote => pick('Edit note', 'Επεξεργασία σημείωσης');
  String get duplicateNote => pick('Duplicate note', 'Δημιουργία αντιγράφου');
  String get connectToNote => pick('Connect to note', 'Σύνδεση με σημείωση');
  String get showInAnotherWorkspace =>
      pick('Show in another workspace', 'Εμφάνιση σε άλλον χώρο εργασίας');
  String get removeFromThisWorkspace => pick(
    'Remove from this workspace',
    'Αφαίρεση από αυτόν τον χώρο εργασίας',
  );
  String get moveToTrash => pick('Move to Trash', 'Μεταφορά στον Κάδο');
  String get noteOptions => pick('Note options', 'Επιλογές σημείωσης');
  String get tapToStartWriting =>
      pick('Tap to start writing…', 'Πατήστε για να αρχίσετε να γράφετε…');
  String get noteDuplicated =>
      pick('Note duplicated.', 'Δημιουργήθηκε αντίγραφο της σημείωσης.');
  String get movedToTrash => pick(
    'Moved to Trash · Recoverable for 14 days',
    'Μεταφέρθηκε στον Κάδο · Μπορεί να ανακτηθεί για 14 ημέρες',
  );
  String get undo => pick('Undo', 'Αναίρεση');
  String get noteRestored => pick(
    'Note restored to its workspace.',
    'Η σημείωση επαναφέρθηκε στον χώρο εργασίας της.',
  );
  String get deletePermanently =>
      pick('Delete permanently', 'Οριστική διαγραφή');
  String get deletePermanentlyQuestion =>
      pick('Delete permanently?', 'Οριστική διαγραφή;');
  String deletePermanentlyMessage(String title) => pick(
    '“$title” will no longer be recoverable.',
    'Η σημείωση «$title» δεν θα μπορεί πλέον να ανακτηθεί.',
  );
  String get restore => pick('Restore', 'Επαναφορά');
  String daysRemaining(int days) => pick(
    '$days day${days == 1 ? '' : 's'} remaining',
    'Απομέν${days == 1 ? 'ει' : 'ουν'} $days ημέρ${days == 1 ? 'α' : 'ες'}',
  );
  String deletedNotesSummary(int count) => pick(
    '$count deleted note${count == 1 ? '' : 's'} · automatically removed after 14 days',
    '$count διαγραμμέν${count == 1 ? 'η σημείωση' : 'ες σημειώσεις'} · αφαιρούνται αυτόματα μετά από 14 ημέρες',
  );
  String get trashEmpty => pick('Trash is empty.', 'Ο Κάδος είναι άδειος.');

  String get buildWorkspace =>
      pick('Build your workspace', 'Δημιουργήστε τον χώρο εργασίας σας');
  String get createFirstNote =>
      pick('Create your first note', 'Δημιουργήστε την πρώτη σας σημείωση');
  String get createFirstNoteMessage => pick(
    'Create your first note and arrange it anywhere on the canvas.',
    'Δημιουργήστε την πρώτη σας σημείωση και οργανώστε την ελεύθερα στον καμβά.',
  );
  String workspaceEmptyTitle(String name) =>
      pick('$name is empty', 'Ο χώρος «$name» είναι άδειος');
  String get workspaceEmptyMessage => pick(
    'Create a new note or add one of your existing notes here.',
    'Δημιουργήστε νέα σημείωση ή προσθέστε εδώ μία από τις υπάρχουσες σημειώσεις σας.',
  );
  String get createNote => pick('Create note', 'Δημιουργία σημείωσης');
  String get addExistingNote =>
      pick('Add existing note', 'Προσθήκη υπάρχουσας σημείωσης');
  String get everyNoteAlreadyHere => pick(
    'Every note is already in this workspace.',
    'Όλες οι σημειώσεις βρίσκονται ήδη σε αυτόν τον χώρο εργασίας.',
  );
  String get noteAlreadyEverywhere => pick(
    'This note is already in every workspace.',
    'Αυτή η σημείωση βρίσκεται ήδη σε κάθε χώρο εργασίας.',
  );
  String get showNoteInWorkspace =>
      pick('Show note in workspace', 'Εμφάνιση σημείωσης σε χώρο εργασίας');
  String noteAddedToWorkspace(String name) =>
      pick('Note added to $name.', 'Η σημείωση προστέθηκε στον χώρο «$name».');
  String get moveBeforeRemoving => pick(
    'Add the note to another workspace before removing it from this one.',
    'Προσθέστε τη σημείωση σε άλλον χώρο εργασίας πριν την αφαιρέσετε από αυτόν.',
  );
  String get addAnotherBeforeConnecting => pick(
    'Add another note to this workspace before creating a connection.',
    'Προσθέστε ακόμη μία σημείωση σε αυτόν τον χώρο πριν δημιουργήσετε σύνδεση.',
  );
  String get noConnections => pick(
    'No connections yet. Use a note menu to create one.',
    'Δεν υπάρχουν ακόμη συνδέσεις. Χρησιμοποιήστε το μενού μιας σημείωσης για να δημιουργήσετε μία.',
  );
  String get connections => pick('Connections', 'Συνδέσεις');
  String get connectedNotes =>
      pick('Connected notes', 'Συνδεδεμένες σημειώσεις');
  String get pinNote => pick('Pin note', 'Καρφίτσωμα σημείωσης');
  String get unpinNote => pick('Unpin note', 'Ξεκαρφίτσωμα σημείωσης');
  String get pinnedNote => pick('Pinned note', 'Καρφιτσωμένη σημείωση');
  String get outgoingConnection => pick('Outgoing', 'Εξερχόμενη');
  String get incomingConnection => pick('Incoming', 'Εισερχόμενη');
  String get undirectedConnection => pick('Undirected', 'Χωρίς κατεύθυνση');
  String get focusTargetNote =>
      pick('Focus target note', 'Εστίαση στη σημείωση προορισμού');
  String get deleteConnection => pick('Delete connection', 'Διαγραφή σύνδεσης');
  String get manageConnections =>
      pick('Manage connections', 'Διαχείριση συνδέσεων');
  String get createConnection =>
      pick('Create connection', 'Δημιουργία σύνδεσης');
  String get connectionLabel => pick('Connection label', 'Ετικέτα σύνδεσης');
  String get directedConnection =>
      pick('Directed connection', 'Κατευθυνόμενη σύνδεση');
  String get targetNote => pick('Target note', 'Σημείωση προορισμού');
  String get nextTaskProgression =>
      pick('Next task progression', 'Επόμενο βήμα εργασίας');
  String get nextTaskProgressionHint => pick(
    'Treat this directed connection as the next step in a task flow.',
    'Χρησιμοποιήστε αυτή την κατευθυνόμενη σύνδεση ως το επόμενο βήμα μιας ροής εργασιών.',
  );
  String get nextTaskBadge => pick('NEXT', 'ΕΠΟΜΕΝΟ');
  String get nextTaskReadyHint => pick(
    'This note is ready as the next task.',
    'Αυτή η σημείωση είναι έτοιμη ως το επόμενο βήμα.',
  );
  String nextTaskReadyMessage(String title) =>
      pick('Next task ready: $title', 'Επόμενο βήμα έτοιμο: $title');
  String get openNextTask => pick('Open', 'Άνοιγμα');

  String get createWorkspace =>
      pick('Create workspace', 'Δημιουργία χώρου εργασίας');
  String get renameWorkspace =>
      pick('Rename workspace', 'Μετονομασία χώρου εργασίας');
  String get deleteWorkspace =>
      pick('Delete workspace', 'Διαγραφή χώρου εργασίας');
  String get workspaceOptions =>
      pick('Workspace options', 'Επιλογές χώρου εργασίας');
  String get workspaceName => pick('Workspace name', 'Όνομα χώρου εργασίας');
  String get workspaceNameHint =>
      pick('University, Work, Ideas…', 'Πανεπιστήμιο, Εργασία, Ιδέες…');
  String get atLeastOneWorkspace => pick(
    'At least one workspace must remain.',
    'Πρέπει να παραμείνει τουλάχιστον ένας χώρος εργασίας.',
  );
  String get deleteWorkspaceQuestion =>
      pick('Delete workspace?', 'Διαγραφή χώρου εργασίας;');
  String deleteWorkspaceMessage(String name) => pick(
    '“$name” will be deleted. Notes shown only there will become unassigned and can be added manually to another workspace; they will not be moved automatically.',
    'Ο χώρος «$name» θα διαγραφεί. Οι σημειώσεις που εμφανίζονται μόνο εκεί θα μείνουν χωρίς χώρο και θα μπορείτε να τις προσθέσετε χειροκίνητα αλλού· δεν θα μεταφερθούν αυτόματα.',
  );
  String get sortNotes => pick('Sort notes', 'Ταξινόμηση σημειώσεων');
  String get sortRecentlyUpdated =>
      pick('Recently updated', 'Πρόσφατα ενημερωμένες');
  String get sortOldestUpdated =>
      pick('Oldest updated', 'Παλαιότερα ενημερωμένες');
  String get sortTitleAscending => pick('Title A → Z', 'Τίτλος Α → Ω');
  String get sortTitleDescending => pick('Title Z → A', 'Τίτλος Ω → Α');
  String get filterNotes => pick('Filter notes', 'Φιλτράρισμα σημειώσεων');
  String get filterAllNotes => pick('All notes', 'Όλες οι σημειώσεις');
  String get filterTaskNotes => pick('Task notes', 'Σημειώσεις με εργασίες');
  String get filterIncompleteTasks =>
      pick('Incomplete tasks', 'Μη ολοκληρωμένες εργασίες');
  String get filterCompletedTasks =>
      pick('Completed tasks', 'Ολοκληρωμένες εργασίες');
  String get searchWorkspace =>
      pick('Search this workspace', 'Αναζήτηση σε αυτόν τον χώρο');
  String get searchTrash => pick('Search Trash', 'Αναζήτηση στον Κάδο');
  String get clearSearch => pick('Clear search', 'Καθαρισμός αναζήτησης');
  String get noSearchResults => pick(
    'No notes match this search.',
    'Δεν βρέθηκαν σημειώσεις που να ταιριάζουν στην αναζήτηση.',
  );
  String get mobileCardsView => pick('Mobile cards', 'Κάρτες κινητού');
  String get mobileCardsExplanation => pick(
    'On phones, notes are shown as touch-friendly cards. Their desktop canvas positions remain unchanged.',
    'Στο κινητό οι σημειώσεις εμφανίζονται ως εύχρηστες κάρτες. Οι θέσεις τους στον καμβά του υπολογιστή δεν αλλάζουν.',
  );
  String get zoomOut => pick('Zoom out', 'Σμίκρυνση');
  String get zoomIn => pick('Zoom in', 'Μεγέθυνση');
  String get fitNotes => pick('Fit notes', 'Προσαρμογή σημειώσεων');

  String get closeEditor => pick('Close editor', 'Κλείσιμο επεξεργασίας');
  String get addTitleOrContent => pick(
    'Add a title or some content first.',
    'Προσθέστε πρώτα τίτλο ή περιεχόμενο.',
  );
  String get untitledNote => pick('Untitled note', 'Σημείωση χωρίς τίτλο');
  String get discardChanges => pick('Discard changes?', 'Απόρριψη αλλαγών;');
  String get unsavedWarning => pick(
    'Your changes have not been saved yet.',
    'Οι αλλαγές σας δεν έχουν αποθηκευτεί ακόμη.',
  );
  String get keepEditing => pick('Keep editing', 'Συνέχεια επεξεργασίας');
  String get discard => pick('Discard', 'Απόρριψη');
  String get noteTitle => pick('Note title', 'Τίτλος σημείωσης');
  String get writingHint => pick(
    'Start writing… Use the toolbar for headings, lists, checklists and emphasis.',
    'Αρχίστε να γράφετε… Χρησιμοποιήστε τη γραμμή εργαλείων για επικεφαλίδες, λίστες, λίστες ελέγχου και έμφαση.',
  );
  String get previewMarkdown => pick('Preview', 'Προεπισκόπηση');
  String get editMarkdown => pick('Edit', 'Επεξεργασία');
  String get unsavedChanges =>
      pick('Unsaved changes', 'Μη αποθηκευμένες αλλαγές');
  String get noChangesYet =>
      pick('No changes yet', 'Δεν υπάρχουν αλλαγές ακόμη');
  String wordCount(int count) => pick(
    '$count word${count == 1 ? '' : 's'}',
    '$count λέξ${count == 1 ? 'η' : 'εις'}',
  );
  String get heading => pick('Heading', 'Επικεφαλίδα');
  String get bold => pick('Bold', 'Έντονα');
  String get italic => pick('Italic', 'Πλάγια');
  String get bulletedList => pick('Bulleted list', 'Λίστα με κουκκίδες');
  String get numberedList => pick('Numbered list', 'Αριθμημένη λίστα');
  String get checklist => pick('Checklist', 'Λίστα ελέγχου');
  String get quote => pick('Quote', 'Παράθεση');
  String get inlineCode => pick('Inline code', 'Ενσωματωμένος κώδικας');

  String get accountSecurity =>
      pick('Account and security', 'Λογαριασμός και ασφάλεια');
  String get accountComingSafely => pick(
    'Account support will be enabled only after the existing data is migrated safely.',
    'Η λειτουργία λογαριασμού θα ενεργοποιηθεί μόνο αφού μεταφερθούν με ασφάλεια τα υπάρχοντα δεδομένα.',
  );

  String operationFailed(String action, Object error) =>
      pick('$action failed: $error', 'Αποτυχία ενέργειας «$action»: $error');
}
