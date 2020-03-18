(in-package :keymap)

(defstruct modifier
  (string "" :type string)
  (shortcut "" :type string))

(declaim (ftype (function ((or string modifier) (or string modifier)) boolean) modifier=))
(defun modifier= (string-or-modifier1 string-or-modifier2)
  (unless (or (modifier-p string-or-modifier1)
              (modifier-p string-or-modifier2))
    (error 'bad-modifier :message "At least one of the arguments must be a modifier."))
  (flet ((match-modifier (modifier string)
           (or (string= (modifier-string modifier) string)
               (string= (modifier-shortcut modifier) string))))
    (cond
      ((stringp string-or-modifier1)
       (match-modifier string-or-modifier2 string-or-modifier1))
      ((stringp string-or-modifier2)
       (match-modifier string-or-modifier1 string-or-modifier2))
      (t
       (or (string= (modifier-string string-or-modifier1)
                    (modifier-string string-or-modifier2))
           (string= (modifier-shortcut string-or-modifier1)
                    (modifier-shortcut string-or-modifier2)))))))

(defmethod fset:compare ((x modifier) (y modifier))
  "Needed to user the KEY structure as keys in Fset maps."
  (fset:compare-lexicographically (modifier-string x) (modifier-string y)))

(defvar +control+ (make-modifier :string "control" :shortcut "C"))
(defvar +meta+ (make-modifier :string "meta" :shortcut "M"))
(defvar +shift+ (make-modifier :string "shift" :shortcut "s"))
(defvar +super+ (make-modifier :string "super" :shortcut "S"))
(defvar +hyper+ (make-modifier :string "hyper" :shortcut "H"))

(defparameter *modifier-list*
  (list +control+ +meta+ +shift+ +super+ +hyper+)
  "List of known modifiers.
`make-key' and `define-key' raise an error when setting a modifier that is not
in this list.")

(deftype key-status-type ()
  `(or (eql :pressed) (eql :released)))

;; Must be a structure so that it can served as a key in a hash-table with
;; #'equalp tests.
(defstruct (key (:constructor %make-key (code value modifiers status))
                (:copier %copy-key))
  (code 0 :type integer) ; TODO: Can a keycode be 0?  I think not, so 0 might be a good non-value.
  (value "" :type string)
  (modifiers (fset:set) :type fset:wb-set)
  (status :pressed :type key-status-type))

(defun key= (key1 key2)
  "Two keys are equal if the have the same modifiers, status and key code.
If codes don't match, the values are compared instead.  This way, code-matching
keys match before the value which is usually what the users want when they
specify a key-code binding."
  (and (or (and (not (zerop (key-code key1)))
                (= (key-code key1)
                   (key-code key2)))
           (string= (key-value key1)
                    (key-value key2)))
       (fset:equal? (key-modifiers key1)
                    (key-modifiers key2))
       (eq (key-status key1)
           (key-status key2))))

(declaim (ftype (function ((or string modifier)) modifier) modspec->modifier))
(defun modspec->modifier (string-or-modifier)
  "Return the `modifier' corresponding to STRING-OR-MODIFIER."
  (if (modifier-p string-or-modifier)
      string-or-modifier
      (let ((modifier (find-if (alex:curry #'modifier= string-or-modifier) *modifier-list*)))
        (or modifier
            (error 'bad-modifier
                   :message (format nil "Unknown modifier ~a" string-or-modifier))))))

(declaim (ftype (function ((or list-of-strings
                               fset:wb-set))
                          fset:wb-set)
                modspecs->modifiers))
(defun modspecs->modifiers (strings-or-modifiers)
  "Return the list of `modifier's corresponding to STRINGS-OR-MODIFIERS."
  (flet ((list-difference (list1 list2)
           (dolist (list2-elt list2 list1)
             (setf list1 (delete list2-elt list1 :count 1)))))
    (if (fset:set? strings-or-modifiers)
        strings-or-modifiers
        (coerce  (fset:convert 'fset:set
                               (let* ((mods (mapcar #'modspec->modifier strings-or-modifiers))
                                      (no-dups-mods (delete-duplicates mods :test #'modifier=)))
                                 (when (/=  (length mods) (length no-dups-mods))
                                   (warn "Duplicate modifiers: ~a"
                                         (mapcar #'modifier-string
                                                 (list-difference mods no-dups-mods))))
                                 no-dups-mods))
                 'fset:wb-set))))

(declaim (ftype (function (&key (:code integer) (:value string)
                                (:modifiers list) (:status keyword))
                          key)
                make-key))
(defun make-key (&key (code 0 explicit-code) (value "" explicit-value)
                      modifiers
                      (status :pressed))
  "Return new `key'.
Modifiers can be either a `modifier' type or a string that will be looked up in
`*modifier-list*'."
  (unless (or explicit-code explicit-value)
    (error 'make-key-required-arg))
  (%make-key
   code
   value
   (modspecs->modifiers modifiers)
   status))

(declaim (ftype (function (key &key (:code integer) (:value string)
                               (:modifiers fset:wb-set) (:status keyword))
                          key)
                copy-key))
(defun copy-key (key &key (code (key-code key)) (value (key-value key))
                        (modifiers (key-modifiers key))
                        (status (key-status key)))
  (let ((new-key (%copy-key key)))
    (setf (key-value new-key) value
          (key-code new-key) code
          (key-status new-key) status
          (key-modifiers new-key) (modspecs->modifiers modifiers))
    new-key))

(defmethod fset:compare ((x key) (y key))
  "Needed to user the KEY structure as keys in Fset maps."
  (if (key= x y)
      :equal
      :unequal))

(declaim (ftype (function (string) key) keyspec->key))
(defun keyspec->key (string)
  "Parse STRING and return a new `key'.
The specifier is expected to be in the form

  MOFIFIERS-CODE/VALUE

MODIFIERS are hyphen-separated modifiers as per `*modifier-list*'.
CODE/VALUE is either a code that starts with '#' or a key symbol.

Note that '-' or '#' as a last character is supported, e.g. 'control--' and
'control-#' are valid."
  (when (string= string "")
    (error 'empty-keyspec))
  (let* ((last-nonval-hyphen (or (position #\- string :from-end t
                                                      :end (1- (length string)))
                                 -1))
         (code 0)
         (value "")
         (code-or-value (subseq string (1+ last-nonval-hyphen)))
         (rest (subseq string 0 (1+ last-nonval-hyphen)))
         (modifiers (butlast (str:split "-" rest))))
    (when (find "" modifiers :test #'string=)
      (error 'empty-modifiers))
    (when (and (<= 2 (length code-or-value))
               (string= (subseq code-or-value (1- (length code-or-value)))
                        "-"))
      (error 'empty-value))
    (if (and (<= 2 (length code-or-value))
             (string= "#" (subseq code-or-value 0 1)))
        (setf code (or (parse-integer code-or-value :start 1 :junk-allowed t)
                       code))
        (setf value code-or-value))
    (make-key :code code :value value :modifiers modifiers)))

(declaim (ftype (function (string) list-of-keys) keyspecs->keys))
(defun keyspecs->keys (spec)
  "Parse SPEC and return corresponding list of keys."
  ;; TODO: Return nil if SPEC is invalid?
  (let* ((result (str:split " " spec :omit-nulls t)))
    (mapcar #'keyspec->key result)))

(declaim (ftype (function (string) string) toggle-case))
(defun toggle-case (string)
  "Return the input with reversed case if it has only one character."
  (if (= 1 (length string))
      (let ((down (string-downcase string)))
        (if (string= down string)
            (string-upcase string)
            down))
      string))

(defun translate-remove-shift-toggle-case (keys)
  "With shift, keys without shift and with their key value case reversed:
'shift-a shift-B' -> 'A b'."
  (let ((shift? (find +shift+ keys :key #'key-modifiers :test #'fset:find)))
    (when shift?
      (mapcar (lambda (key)
                (copy-key key :modifiers (fset:less (key-modifiers key) +shift+)
                              :value (toggle-case (key-value key))))
              keys))))

(defun translate-remove-shift (keys)
  "With shift, keys without shift: 'shift-a' -> 'a'."
  (let ((shift? (find +shift+ keys :key #'key-modifiers :test #'fset:find)))
    (when shift?
      (mapcar (lambda (key)
                (copy-key key :modifiers (fset:less (key-modifiers key) +shift+)))
              keys))))

(defun translate-remove-but-first-control (keys)
  "With control, keys without control except for the first key:
'C-x C-c' -> 'C-x c'."
  (let ((control? (find +control+ (rest keys) :key #'key-modifiers :test #'fset:find)))
    (when control?
      (cons (first keys)
            (mapcar (lambda (key)
                      (copy-key key :modifiers (fset:less (key-modifiers key) +control+)))
                    (rest keys))))))

(defun translate-remove-shift-but-first-control (keys)
  "With control and shift, keys without control except for the first key and
without shift everywhere: 'C-shift-C C-shift-f' -> 'C-C f. "
  (let ((shift? (find +shift+ keys :key #'key-modifiers :test #'fset:find))
        (control? (find +control+ (rest keys) :key #'key-modifiers :test #'fset:find)))
    (when (and control? shift?)
               (cons (copy-key (first keys)
                               :modifiers (fset:less (key-modifiers (first keys)) +shift+))
                     (mapcar (lambda (key)
                               (copy-key key :modifiers (fset:set-difference (key-modifiers key)
                                                                             (fset:set +control+ +shift+))))
                             (rest keys))))))

(defun translate-remove-shift-but-first-control-toggle-case (keys)
  "With control and shift, keys without control except for the first key and
without shift everywhere: 'C-shift-C C-shift-f' -> 'C-c F. "
  (let ((control? (find +control+ (rest keys) :key #'key-modifiers :test #'fset:find))
        (shift? (find +shift+ keys :key #'key-modifiers :test #'fset:find)))
    (when (and control? shift?)
               (cons (copy-key (first keys)
                               :value (toggle-case (key-value (first keys)))
                               :modifiers (fset:less (key-modifiers (first keys)) +shift+))
                     (mapcar (lambda (key)
                               (copy-key key
                                         :value (toggle-case (key-value key))
                                         :modifiers (fset:set-difference (key-modifiers key)
                                                                         (fset:set +control+ +shift+))))
                             (rest keys))))))

(defun translate-shift-control-combinations (keys)
  "Return the successive translations of
- `translate-remove-shift-toggle-case'
- `translate-remove-shift'
- `translate-remove-but-first-control'
- `translate-remove-shift-but-first-control'
- `translate-remove-shift-but-first-control-toggle-case'"
  (delete nil
          (mapcar (lambda (translator) (funcall translator keys))
                  (list #'translate-remove-shift-toggle-case
                        #'translate-remove-shift
                        #'translate-remove-but-first-control
                        #'translate-remove-shift-but-first-control
                        #'translate-remove-shift-but-first-control-toggle-case))))

(defvar *default-translator* #'translate-shift-control-combinations
  "Default key translator to use in `keymap' objects.")

;; TODO: Enable override of default and translator in lookup?
(defclass keymap ()
  ((entries :accessor entries
            :initarg :entries
            :initform nil
            :type fset:wb-map
            :documentation
            "Hash table of which the keys are key-chords and the values are a
symbol or a keymap.")
   (parents :accessor parents
            :initarg :parents
            :initform nil
            :type list-of-keymaps
            :documentation "List of parent keymaps.
Parents are ordered by priority, the first parent has highest priority.")
   (default :accessor default
            :initarg :default
            :initform nil
            :type t
            :documentation "Default value when no binding is found.")
   (translator :accessor translator
               :initarg :translator
               :initform *default-translator*
               :type function
               :documentation "When no binding is found, call this function to
generate new bindings to lookup.  The function takes a list of `key' objects and
returns a list of list of keys.")))

(declaim (ftype (function (&key (:default t)
                                (:translator function)
                                (:parents list-of-keymaps))
                          keymap)
                make-keymap))
(defun make-keymap (&key default translator parents)
  ;; We coerce to 'keymap because otherwise SBCL complains "type assertion too
  ;; complex to check: (VALUES KEYMAP::KEYMAP &REST T)."
  (coerce
   (make-instance 'keymap
                  :parents parents
                  :default default
                  :translator (or translator *default-translator*)
                  ;; We cannot use the standard (make-hash-table :test #'equalp)
                  ;; because then (set "a") and (set "A") would be the same thing.
                  :entries (fset:empty-map default))
   'keymap))

(defun keymap-p (object)
  (typep object 'keymap))

(deftype keyspecs-type ()               ; TODO: Rename to KEYDESC?
  `(satisfies keyspecs->keys))

;; We need a macro to check that bindings are valid at compile time.
;; This is because most Common Lisp implementations or not capable of checking
;; types that use `satisfies' for non-top-level symbols.
;; We can verify this with:
;;
;;   (compile 'foo (lambda () (keymap::define-key keymap "C-x C-f" 'find-file)))
(defmacro define-key (keymap keyspecs bound-value &rest more-keyspecs-value-pairs)
  "Bind KEYS to BOUND-VALUE in KEYMAP.
Return KEYMAP.

KEYS is either a `keyspecs-type' or a list of arguments passed to invocations
of `make-key's.

Examples:

  (define-key foo-map \"C-x C-f\" 'find-file)

  (define-key foo-map
              \"C-x C-f\" 'find-file
              \"C-h k\" 'describe-key)

\"C-M-1 x\" on a QWERTY:

  (define-key foo-map '((:code 10 :modifiers (\"C\" \"M\") (:value \"x\"))) 'find-file)

or the shorter:

  (define-key foo-map \"C-M-#1\" 'find-file)"
  ;; The type checking of KEYMAP is done by `define-key*'.
  (let ((keyspecs-value-pairs (append (list keyspecs bound-value) more-keyspecs-value-pairs)))
    (loop :for (keyspecs bound-value . rest) :on keyspecs-value-pairs :by #'cddr
          :do (check-type keyspecs (or keyspecs-type list)))
    `(progn
       ,@(loop :for (keyspecs bound-value . rest) :on keyspecs-value-pairs :by #'cddr
               :collect (list 'define-key* keymap keyspecs bound-value))
       ,keymap)))

(declaim (ftype (function (keymap (or keyspecs-type list) (or keymap t))) define-key*))
(defun define-key* (keymap keyspecs bound-value)
  (let ((keys (if (listp keyspecs)
                  (mapcar (alex:curry #'apply #'make-key) keyspecs)
                  (keyspecs->keys keyspecs))))
    (bind-key keymap keys bound-value)))

(declaim (ftype (function (keymap list-of-keys (or keymap t)) keymap) bind-key))
(defun bind-key (keymap keys bound-value)
  "Recursively bind the KEYS to keymaps starting from KEYMAP.
The last key is bound to BOUND-VALUE.
Return KEYMAP."
  (if (= (length keys) 1)
      (progn
        (when (fset:@ (entries keymap) (first keys))
          ;; TODO: Notify caller properly?
          (warn "Key was bound to ~a" (fset:@ (entries keymap) (first keys))))
        (setf (fset:@ (entries keymap) (first keys)) bound-value))
      (let ((submap (fset:@ (entries keymap) (first keys))))
        (unless (keymap-p submap)
          (setf submap (make-keymap :default (default keymap)
                                    :translator (translator keymap)))
          (setf (fset:@ (entries keymap) (first keys)) submap))
        (bind-key submap (rest keys) bound-value)))
  keymap)

(declaim (ftype (function (keymap
                           list-of-keys
                           list-of-keymaps)
                          (or keymap t))
                lookup-keys-in-keymap))
(defun lookup-keys-in-keymap (keymap keys visited)
  "Return bound value or keymap for KEYS.
Return nil when KEYS is not found in KEYMAP.
VISITED is used to detect cycles."
  (when keys
    (let ((hit (fset:@ (entries keymap) (first keys))))
      (when hit
        (if (and (keymap-p hit)
                 (rest keys))
            (lookup-key* hit (rest keys) visited)
            hit)))))

(declaim (ftype (function (keymap
                           list-of-keys
                           list-of-keymaps)
                          (or keymap t))
                lookup-translated-keys))
(defun lookup-translated-keys (keymap keys visited)
  "Return the bound value or keymap associated to KEYS in KEYMAP.
Return nil if there is none.
Keymap parents are looked up one after the other.
VISITED is used to detect cycles."
  (or (lookup-keys-in-keymap keymap keys visited)
      (some (lambda (map)
              (lookup-key* map keys visited))
            (parents keymap))))

(declaim (ftype (function (keymap
                           list-of-keys
                           list-of-keymaps)
                          (or keymap t))
                lookup-key*))
(defun lookup-key* (keymap keys visited)
  "Internal function, see `lookup-key' for the user-facing function.
VISITED is used to detect cycles."
  (if (find keymap visited)
      (warn "Cycle detected in keymap ~a" keymap)
      (some (lambda (keys)
              (lookup-translated-keys keymap keys (cons keymap visited)))
            (cons keys (funcall (or (translator keymap) (constantly nil)) keys)))))

(declaim (ftype (function (list-of-keys keymap &rest keymap) (or keymap t)) lookup-key))
(defun lookup-key (keys keymap &rest more-keymaps)   ; TODO: Rename to lookup-keys? lookup-binding?
  "Return the value bound to KEYS in KEYMAP.
Return the default value of the first KEYMAP if no binding is found.

The second return value is T if a binding is found, NIL otherwise.

First keymap parents are lookup up one after the other.
Then keys translation are looked up one after the other.
The same is done for the successive MORE-KEYMAPS."
  (or (values (some (alex:rcurry #'lookup-key* keys '()) (cons keymap more-keymaps))
              t)
      (values (default keymap)
              nil)))

(defparameter *print-shortcut* t
  "Whether to print the short form of the modifiers.")

(declaim (ftype (function (key) keyspecs-type) key->keyspec))
(defun key->keyspec (key)
  "Return the keyspec of KEY."
  (let ((value (if (zerop (key-code key))
                   (key-value key)
                   (format nil "#~a" (key-code key))))
        (modifiers (fset:reduce (lambda (&rest mods) (str:join "-" mods))
                                (key-modifiers key)
                                :key (if *print-shortcut*
                                         #'modifier-shortcut
                                         #'modifier-string))))
    (coerce (str:concat (if (str:empty? modifiers) "" (str:concat modifiers "-"))
                        value)
            'keyspecs-type)))

(declaim (ftype (function (list-of-keys) keyspecs-type) keys->keyspecs))
(defun keys->keyspecs (keys)
  "Return a keyspecs"
  (coerce (str:join " " (mapcar #'key->keyspec keys)) 'keyspecs-type))

(declaim (ftype (function (keymap &optional list-of-keymaps) fset:map) keymap->map*))
(defun keymap->map* (keymap &optional visited)
  "Return a map of (KEYSPEC SYM) from KEYMAP."
  (flet ((fold-keymap (result key sym)
           (let ((keyspec (key->keyspec key)))
             (if (keymap-p sym)
                 (cond
                   ((find sym visited)
                    (warn "Cycle detected in keymap ~a" keymap)
                    result)
                   (t
                    (fset:map-union result
                                    (fset:image (lambda (subkey subsym)
                                                  (values (format nil "~a ~a" keyspec subkey)
                                                          subsym))
                                                (keymap->map* sym (cons sym visited))))))
                 (fset:with result keyspec sym)))))
    (coerce
     (fset:reduce #'fold-keymap (entries keymap)
                  :initial-value (fset:empty-map))
     'fset:map)))

(declaim (ftype (function (keymap &rest keymap) hash-table) keymap->map))
(defun keymap->map (keymap &rest more-keymaps)
  "Return a hash-table of (KEYSPEC SYM) from KEYMAP.
Parent bindings are not listed; see `keymap-with-parents->map' instead.
This is convenient if the caller wants to list all the bindings.
When multiple keymaps are provided, return the union of the `fset:map' of each arguments.
Keymaps are ordered by precedence, highest precedence comes first."
  (let ((keymaps (reverse (cons keymap more-keymaps))))
    (coerce
     (fset:convert 'hash-table
                   (reduce #'fset:map-union
                           (mapcar #'keymap->map* keymaps)))
     'hash-table)))

(declaim (ftype (function (keymap) hash-table) keymap-with-parents->map))
(defun keymap-with-parents->map (keymap)
  "List bindings in KEYMAP and all its parents.
See `keymap->map'."
  (labels ((list-keymaps (keymap visited)
             (if (find keymap visited)
                 (progn
                   (warn "Cycle detected in parent keymap ~a" keymap)
                   '())
                 (progn
                   (cons keymap
                         (alex:mappend (alex:rcurry #'list-keymaps (cons keymap visited))
                                       (parents keymap)))))))
    (apply #'keymap->map (list-keymaps keymap '()))))

(declaim (ftype (function (keymap &rest keymap) (or keymap null)) compose))
(defun compose (keymap &rest more-keymaps)
  "Return a new keymap that's the composition of all given KEYMAPS.
KEYMAPS are composed by order of precedence, first keymap being the one with
highest precedence."
  (flet ((stable-union (list1 list2)
           (delete-duplicates (append list1 list2)
                              :from-end t)))
    (let ((keymaps (cons keymap more-keymaps)))
      (cond
        ((uiop:emptyp keymaps)
         nil)
        ((= 1 (length keymaps))
         (first keymaps))
        (t
         (let ((keymap1 (first keymaps))
               (keymap2 (second keymaps))
               (merge (make-keymap)))
           (setf (default merge) (default keymap1))
           (setf (translator merge) (translator keymap1))
           (setf (parents merge) (stable-union (parents keymap1) (parents keymap2)))
           (setf (entries merge) (fset:map-union (entries keymap2) (entries keymap1)))
           (apply #'compose merge (rest (rest keymaps)))))))))

(declaim (ftype (function (t keymap &key (:test function)) list-of-strings) binding-keys*))
(defun binding-keys* (binding keymap &key (test #'eql))
  "Return a the list of `keyspec's bound to BINDING in KEYMAP.
The list is sorted alphabetically to ensure reproducible results.
Comparison against BINDING is done with TEST."
  (let ((result '()))
    (maphash (lambda (key sym)
               (when (funcall test binding sym)
                 (push key result)))
             (keymap->map keymap))
    (sort result #'string<)))

(declaim (ftype (function (t keymap &key (:more-keymaps list-of-keymaps) (:test function)) list) binding-keys))
(defun binding-keys (bound-value keymap &key more-keymaps (test #'eql)) ; TODO: Return hash-table or alist?
  "Return an alist of (keyspec keymap) for all the `keyspec's bound to BINDING in KEYMAP.
Comparison against BINDING is done with TEST."
  (coerce (alex:mappend (lambda (keymap)
                          (let ((hit (binding-keys* bound-value keymap :test test)))
                            (when hit
                              (mapcar (alex:rcurry #'list keymap) hit))))
                        (cons keymap more-keymaps))
          'list))

;; TODO: Remap binding, e.g.
;; (define-key *foo-map* (remap 'bar-sym) 'new-sym)

;; TODO: Add timeout support, e.g. "jk" in less than 0.1s could be ESC in VI-style.
