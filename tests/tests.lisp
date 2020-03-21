(in-package :cl-user)

(prove:plan nil)

(defun empty-keymap (&rest parents)
  (apply #'keymap:make-keymap "anonymous" parents))

(prove:subtest "Make key"
  (let* ((key (keymap:make-key :code 38 :value "a" :modifiers '("C")))
         (mod (first (fset:convert 'list (keymap:key-modifiers key)))))
    (prove:is (keymap:key-code key)
              38)
    (prove:is (keymap:key-value key)
              "a")
    (prove:is mod "C" :test #'keymap:modifier=)
    (prove:is mod "control" :test #'keymap:modifier=)
    (prove:is mod keymap:+control+ :test #'keymap:modifier=)
    (prove:isnt mod "" :test #'keymap:modifier=)
    (prove:isnt mod "M" :test #'keymap:modifier=)
    (prove:isnt mod "meta" :test #'keymap:modifier=)))

(prove:subtest "Make bad key"
  (prove:is-error (keymap:make-key :value "a" :status :dummy)
                  'type-error)
  (prove:is-error (keymap:make-key :value "a" :modifiers '("Z"))
                  'keymap:bad-modifier)
  (prove:is-error (keymap:make-key :status :pressed)
                  'keymap:make-key-required-arg))

(prove:subtest "Make same key"
  (prove:is (keymap:make-key :value "a" :modifiers '("C" "M"))
            (keymap:make-key :value "a" :modifiers '("M" "C"))
            :test #'keymap:key=)
  (prove:is (keymap:make-key :value "a" :modifiers '("C"))
            (keymap:make-key :value "a" :modifiers '("control"))
            :test #'keymap:key=))

(prove:subtest "Make key with duplicate modifiers (trigger warning)"
  (prove:is (keymap:make-key :value "a" :modifiers '("C" "control"))
            (keymap:make-key :value "a" :modifiers '("C"))
            :test #'keymap:key=))

(prove:subtest "Make different key"
  (prove:isnt (keymap:make-key :value "a")
              (keymap:make-key :value "A")
              :test #'keymap:key=))

(prove:subtest "Keyspec->key"
  (prove:is (keymap::keyspec->key "a")
            (keymap:make-key :value "a")
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C-a")
            (keymap:make-key :value "a" :modifiers '("C"))
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C-M-a")
            (keymap:make-key :value "a" :modifiers '("C" "M"))
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C--")
            (keymap:make-key :value "-" :modifiers '("C"))
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C-M--")
            (keymap:make-key :value "-" :modifiers '("C" "M"))
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C-#")
            (keymap:make-key :value "#" :modifiers '("C"))
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "#")
            (keymap:make-key :value "#")
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "-")
            (keymap:make-key :value "-")
            :test #'keymap:key=)
  (prove:is (keymap::keyspec->key "C-#10")
            (keymap:make-key :code 10 :modifiers '("C"))
            :test #'keymap:key=)
  (prove:is-error (keymap::keyspec->key "")
                  'keymap:empty-keyspec)
  (prove:is-error (keymap::keyspec->key "C-")
                  'keymap:empty-value)
  (prove:is-error (keymap::keyspec->key "C---")
                  'keymap:empty-modifiers))

(defun binding= (keys1 keys2)
  (not (position nil (mapcar #'keymap:key= keys1 keys2))))

(prove:subtest "Keyspecs->keys"
  (prove:is (keymap::keyspecs->keys "C-x C-f")
            (list (keymap:make-key :value "x" :modifiers '("C"))
                  (keymap:make-key :value "f" :modifiers '("C")))
            :test #'binding=)
  (prove:is (keymap::keyspecs->keys "  C-x   C-f  ")
            (list (keymap:make-key :value "x" :modifiers '("C"))
                  (keymap:make-key :value "f" :modifiers '("C")))
            :test #'binding=))

(prove:subtest "define-key & lookup-key"
  (let ((keymap (empty-keymap)))
    (keymap:define-key keymap "C-x" 'foo)
    (prove:is (keymap:lookup-key "C-x" keymap)
              'foo)
    (keymap:define-key keymap "C-x" 'foo2)
    (prove:is (keymap:lookup-key "C-x" keymap)
              'foo2)
    (keymap:define-key keymap "C-c C-f" 'bar)
    (prove:is (keymap:lookup-key "C-c C-f" keymap)
              'bar)
    (keymap:define-key keymap "C-c C-h" 'bar2)
    (prove:is (keymap:lookup-key "C-c C-h" keymap)
              'bar2)))

(prove:subtest "define-key & multiple bindings"
  (let ((keymap (empty-keymap)))
    (keymap:define-key keymap
      "C-x" 'foo
      "C-c" 'bar)
    (prove:is (keymap:lookup-key "C-x" keymap)
              'foo)
    (prove:is (keymap:lookup-key "C-c" keymap)
              'bar)))

(prove:subtest "define-key & lookup-key with parents"
  (let* ((parent1 (empty-keymap))
         (parent2 (empty-keymap))
         (keymap (empty-keymap parent1 parent2)))
    (keymap:define-key parent1 "x" 'parent1-x)
    (keymap:define-key parent1 "a" 'parent1-a)
    (keymap:define-key parent2 "x" 'parent2-x)
    (keymap:define-key parent2 "b" 'parent2-b)
    (prove:is (keymap:lookup-key "x" keymap)
              'parent1-x)
    (prove:is (keymap:lookup-key "a" keymap)
              'parent1-a)
    (prove:is (keymap:lookup-key "b" keymap)
              'parent2-b)))

(prove:subtest "define-key & lookup-key with prefix keymap"
  (let ((keymap (empty-keymap))
        (prefix (empty-keymap)))
    (keymap:define-key keymap "C-c" prefix)
    (keymap:define-key prefix "x" 'prefix-sym)
    (prove:is (keymap:lookup-key "C-c x" keymap)
              'prefix-sym)))

(prove:subtest "define-key & lookup-key with cycle"
  (let ((keymap (empty-keymap))
        (parent1 (empty-keymap))
        (parent2 (empty-keymap)))
    (push parent1 (keymap:parents keymap))
    (push parent2 (keymap:parents parent1))
    (push keymap (keymap:parents parent2))
    (prove:is (keymap:lookup-key "x" keymap)
              nil)))

(prove:subtest "Translator"
  (let ((keymap (empty-keymap)))
    (keymap:define-key keymap "A b" 'foo)
    (prove:is (keymap:lookup-key "shift-a shift-B" keymap)
              'foo)
    (keymap:define-key keymap "c" 'bar)
    (prove:is (keymap:lookup-key "shift-c" keymap)
              'bar)
    (keymap:define-key keymap "C-x c" 'baz)
    (prove:is (keymap:lookup-key "C-x C-c" keymap)
              'baz)
    (keymap:define-key keymap "C-c F" 'qux)
    (prove:is (keymap:lookup-key "C-shift-c C-shift-F" keymap)
              'qux)
    (keymap:define-key keymap "1" 'quux)
    (prove:is (keymap:lookup-key "shift-1" keymap)
              'quux)
    (keymap:define-key keymap "return" 'ret)
    (prove:is (keymap:lookup-key "shift-return" keymap)
              'ret)))

(prove:subtest "Translator: Ensure other keymaps have priority over translations"
  (let ((keymap (empty-keymap))
        (keymap2 (empty-keymap)))
    (keymap:define-key keymap "g g" 'prefix-g)
    (keymap:define-key keymap2 "G" 'up-g)
    (prove:is (keymap:lookup-key "s-G" (list keymap keymap2))
              'up-g)))

(prove:subtest "keys->keyspecs"
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :code 10 :value "a")))
            "#10")
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a")
                                          (keymap:make-key :value "b")))
            "a b")
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a" :modifiers '("C"))))
            "C-a")
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a" :modifiers '("C" "M"))))
            "C-M-a")
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a" :modifiers '("M" "C"))))
            "C-M-a")
  (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a" :modifiers '("C" "M"))
                                          (keymap:make-key :value "x" :modifiers '("super" "hyper"))))
            "C-M-a H-S-x")
  (let ((keymap:*print-shortcut* nil))
    (prove:is (keymap:keys->keyspecs (list (keymap:make-key :value "a" :modifiers '("C"))))
              "control-a")))

(prove:subtest "keymap->map"
  (let ((keymap (empty-keymap))
        (keymap2 (empty-keymap)))
    (keymap:define-key keymap "a" 'foo-a)
    (keymap:define-key keymap "b" 'foo-b)
    (keymap:define-key keymap "k" keymap2)
    (keymap:define-key keymap2 "a" 'bar-a)
    (keymap:define-key keymap2 "c" 'bar-c)
    (prove:is (fset:convert 'fset:map (keymap:keymap->map keymap))
              (fset:map ("a" 'foo-a)
                        ("b" 'foo-b)
                        ("k a" 'bar-a)
                        ("k c" 'bar-c))
              :test #'fset:equal?)
    (prove:is (fset:convert 'fset:map (keymap:keymap->map keymap keymap2))
              (fset:map ("a" 'foo-a)
                        ("b" 'foo-b)
                        ("c" 'bar-c)
                        ("k a" 'bar-a)
                        ("k c" 'bar-c))
              :test #'fset:equal?)
    (prove:is (fset:convert 'fset:map (keymap:keymap->map keymap2 keymap))
              (fset:map ("a" 'bar-a)
                        ("b" 'foo-b)
                        ("c" 'bar-c)
                        ("k a" 'bar-a)
                        ("k c" 'bar-c))
              :test #'fset:equal?)))

(prove:subtest "keymap->map with cycles" ; TODO: Can we check warnings?
  (let ((keymap (empty-keymap))
        (keymap2 (empty-keymap)))
    (keymap:define-key keymap "k" keymap2)
    (keymap:define-key keymap2 "a" keymap)
    (prove:is (fset:convert 'fset:map (keymap:keymap->map keymap))
              (fset:empty-map)
              :test #'fset:equal?))
  (let ((keymap (empty-keymap))
        (keymap2 (empty-keymap))
        (keymap3 (empty-keymap)))
    (keymap:define-key keymap "k" keymap2)
    (keymap:define-key keymap2 "a" keymap3)
    (keymap:define-key keymap3 "b" keymap)
    (prove:is (fset:convert 'fset:map (keymap:keymap->map keymap))
              (fset:empty-map)
              :test #'fset:equal?)))

(prove:subtest "keymap-with-parents->map"
  (let* ((grand-parent (empty-keymap))
         (parent1 (empty-keymap))
         (parent2 (empty-keymap grand-parent))
         (keymap (empty-keymap parent1 parent2)))
    (keymap:define-key keymap "a" 'foo-a)
    (keymap:define-key parent1 "b" 'bar-b)
    (keymap:define-key parent2 "c" 'qux-c)
    (keymap:define-key grand-parent "d" 'quux-d)
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap))
              (fset:map ("a" 'foo-a)
                        ("b" 'bar-b)
                        ("c" 'qux-c)
                        ("d" 'quux-d))
              :test #'fset:equal?)
    (keymap:define-key parent2 "d" 'qux-d)
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap))
              (fset:map ("a" 'foo-a)
                        ("b" 'bar-b)
                        ("c" 'qux-c)
                        ("d" 'qux-d))
              :test #'fset:equal?)
    (keymap:define-key parent1 "c" 'bar-c)
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap))
              (fset:map ("a" 'foo-a)
                        ("b" 'bar-b)
                        ("c" 'bar-c)
                        ("d" 'qux-d))
              :test #'fset:equal?)
    (keymap:define-key parent1 "b" 'foo-b)
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap))
              (fset:map ("a" 'foo-a)
                        ("b" 'foo-b)
                        ("c" 'bar-c)
                        ("d" 'qux-d))
              :test #'fset:equal?)))

(prove:subtest "keymap-with-parents->map with cycles" ; TODO: Can we check warnings?
  (let ((keymap1 (empty-keymap))
        (keymap2 (empty-keymap)))
    (push keymap1 (keymap:parents keymap2))
    (push keymap2 (keymap:parents keymap1))
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap1))
              (fset:empty-map)
              :test #'fset:equal?))
  (let ((keymap1 (empty-keymap))
        (keymap2 (empty-keymap))
        (keymap3 (empty-keymap)))
    (push keymap1 (keymap:parents keymap2))
    (push keymap2 (keymap:parents keymap3))
    (push keymap3 (keymap:parents keymap1))
    (prove:is (fset:convert 'fset:map (keymap:keymap-with-parents->map keymap1))
              (fset:empty-map)
              :test #'fset:equal?)))

(prove:subtest "compose-keymaps"
  (let* ((parent1 (empty-keymap))
         (keymap1 (keymap:make-keymap "1" parent1))
         (parent2 (empty-keymap))
         (keymap2 (keymap:make-keymap "2" parent2))
         (keymap3 (empty-keymap)))
    (keymap:define-key keymap1 "a" 'foo-a)
    (keymap:define-key keymap1 "b" 'foo-b)
    (keymap:define-key keymap2 "b" 'bar-b)
    (keymap:define-key keymap2 "c" 'bar-c)
    (keymap:define-key keymap3 "c" 'qux-c)
    (keymap:define-key keymap3 "d" 'qux-d)
    (let ((composition (keymap:compose keymap1 keymap2 keymap3)))
      (prove:is (keymap:name composition)
                "1+2+anonymous")
      (prove:is (fset:convert 'fset:map (keymap:keymap->map composition))
                (fset:map
                 ("a" 'foo-a)
                 ("b" 'foo-b)
                 ("c" 'bar-c)
                 ("d" 'qux-d))
                :test #'fset:equal?)
      (prove:is (keymap:parents composition)
                (list parent1 parent2)))))

(prove:subtest "binding-keys"
  (let* ((keymap1 (empty-keymap))
         (keymap2 (empty-keymap)))
    (keymap:define-key keymap1 "a" 'foo-a)
    (keymap:define-key keymap1 "b" 'foo-b)
    (keymap:define-key keymap1 "C-c a" 'foo-a)

    (prove:is (multiple-value-list (keymap:binding-keys 'foo-a keymap1))
              `(("C-c a" "a")
                (("C-c a" ,keymap1)
                 ("a" ,keymap1))))
    (prove:is (multiple-value-list (keymap:binding-keys 'foo-b keymap1))
              `(("b")
                (("b" ,keymap1))))
    (prove:is (keymap:binding-keys 'missing keymap1)
              nil)
    (keymap:define-key keymap2 "a" 'foo-a)
    (keymap:define-key keymap2 "c" 'foo-a)
    (prove:is (multiple-value-list (keymap:binding-keys 'foo-a (list keymap1 keymap2)))
              `(("C-c a" "a" "c")
                (("C-c a" ,keymap1)
                 ("a" ,keymap1)
                 ("a" ,keymap2)
                 ("c" ,keymap2))))))

(prove:subtest "undefine"
  (let* ((keymap (empty-keymap)))
    (keymap:define-key keymap "a" 'foo-a)
    (keymap:define-key keymap "a" nil)
    (prove:is (keymap::entries keymap)
              (fset:empty-map)
              :test 'fset:equal?)
    (keymap:define-key keymap "C-c b" 'foo-b)
    (keymap:define-key keymap "C-c b" nil)
    (prove:is (keymap::entries keymap)
              (fset:empty-map)
              :test 'fset:equal?)))

(prove:subtest "remap"
  (let* ((keymap (empty-keymap))
         (keymap2 (empty-keymap)))
    (keymap:define-key keymap "a" 'foo-a)
    (keymap:define-key keymap '(:remap foo-a) 'foo-b)
    (prove:is (keymap:lookup-key "a" keymap)
              'foo-b)
    (keymap:define-key keymap2 "b" 'bar-1)
    (keymap:define-key keymap `(:remap bar-1 ,keymap2) 'bar-2)
    (prove:is (keymap:lookup-key "b" keymap)
              'bar-2)))

(prove:subtest "retrieve translated key"
  (let* ((keymap (empty-keymap)))
    (keymap:define-key keymap "a" 'foo-a)
    (multiple-value-bind (hit km key)
        (keymap:lookup-key "s-A" keymap)
      (prove:is hit 'foo-a)
      (prove:is km keymap)
      (prove:is (keymap:keys->keyspecs key) "a"))))

(prove:finalize)
