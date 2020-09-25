(in-package :vk-generator/vk-spec)

;; TODO: much of the stuff below will not be needed or will have to be changed to generate cl bindings

(defclass has-name ()
  ((name
    :initarg :name
    :type string
    :accessor name))
  (:documentation ""))

(defclass vk-element (has-name)
  ((lisp-name
    :initarg :lisp-name
    :type string
    :accessor lisp-name)
   (xml-line
    :initarg :xml-line
    :type bignum
    :initform 0
    :accessor xml-line))
  (:documentation "The base class for elements parsed from a vk.xml.

Slots:
See  NAME       the name of the element in the Vulkan API registry.
See LISP-NAME   the name of the element in the Common Lisp bindings.
See  XML-LINE   the line number in the vk.xml where this element was specified.
"))

(defclass has-extensions ()
  ((extensions
    :initarg :extensions
    :type list ;; string
    :accessor extensions))
  (:documentation "TODO"))

(defclass has-type-name ()
  ((type-name
    :initarg :type-name
    :type string
    :accessor type-name))
  (:documentation "TODO"))

(defclass has-feature ()
  ((feature
    :initarg :feature
    :type string
    :accessor feature))
  (:documentation "TODO"))

(defclass has-array-sizes ()
  ((array-sizes
    :initarg :array-sizes
    :type list ;; string
    :accessor array-sizes))
  (:documentation "TODO"))

;; todo: maybe this is also a vk-element
(defclass name-data (has-name has-array-sizes)
  ((bit-count
    :initarg :bit-count
    :type string
    :accessor name))
  (:documentation "TODO"))

(defclass base-type (vk-element has-type-name)
  ()
  (:documentation "A base type from the Vulkan API Registry.
Base types are aliases for other types named by TYPE. These types are either
types from the Vulkan API registry or C base types.
After the whole vk.xml has been parsed TYPE-NAME must name either a type in
*VK-PLATFORM* or ???. TODO: find out where this is stored in the end.

Slots:
See TYPE   the name of the type of this base type. 

See VK-ELEMENT
See *VK-PLATFORM* 
"))

(defclass bitmask (vk-element)
  ((requirements
   :initarg :requirements
   :type string
   :accessor :requirements)
   (alias
    :initarg :alias
    :type string
    :accessor alias))
  (:documentation "TODO"))

;; TODO: check what compose should do
;; TODO: needs const-pointer-p
;; TODO: needs non-const-pointer-p
;; TODO: needs value-p
(defclass type-info (has-type-name)
  ((prefix
    :initarg :prefix
    :type string
    :accessor prefix)
   (postfix
    :initarg :prefix
    :type string
    :accessor postfix))
  (:documentation "TODO"))

(defclass has-type-info ()
  ((type-info
    :initarg :type-info
    :type type-info
    :accessor type-info))
  (:documentation "TODO"))

(defclass param (vk-element has-type-info has-array-sizes)
  ((len
    :initarg :len
    :type string
    :accessor len)
   (optional-p
    :initarg :optional-p
    :type boolean
    :accessor optional-p))
  (:documentation "TODO"))

(defclass command-alias (vk-element has-extensions has-feature)
  ()
  (:documentation "TODO"))

(defclass command (vk-element has-feature)
  ((alias
    :initarg :alias
    :type hash-table ;; string - command-alias
    :initform (make-hash-table :test 'string=)
    :accessor alias)
   (error-codes
    :initarg :error-codes
    :type list ;; string
    :accessor error-codes)
   (handle
    :initarg :handle
    :type string
    :accessor handle)
   (params
    :initarg :params
    :type list ;; param
    :accessor params)
   (return-type
    :initarg :return-type
    :type string
    :accessor return-type)
   (success-codes
    :initarg :success-codes
    :type list ;; string
    :accessor success-codes))
  (:documentation "TODO"))

(defclass enum-value (vk-element)
  ((vulkan-value ;; I guess this is (name vk-element)
    :initarg :vulkan-value
    :type string
    :accessor vulkan-value)
   (vk-value ;; I guess this is (lisp-name vk-element)
    :initarg :vk-value
    :type string
    :accessor vk-value)
   (single-bit-p
    :initarg :single-bit-p
    :type boolean
    :accessor single-bit-p))
  (:documentation "TODO"))

(defclass enum (vk-element)
  ((alias
    :initarg :alias
    :type string
    :accessor alias)
   (aliases
    :initarg :aliases
    :type hash-table ;; string to (string string)
    :initform (make-hash-table :test 'string=)
    :accessor aliases)
   (bitmask-p
    :initarg :bitmask-p
    :type boolean
    :initform nil
    :accessor bitmask-p)
   (enum-values
    :initarg :enum-values
    :type list ;; enum-value
    :accessor enum-values))
  (:documentation "TODO"))

(defclass extension (vk-element)
  ((deprecated-by
    :initarg :deprecated-by
    :type string
    :accessor deprecated-by)
   (obsoleted-by
    :initarg :obsoleted-by
    :type string
    :accessor obsoleted-by)
   (platform
    :initarg :platform
    :type string
    :accessor platform)
   (promoted-to
    :initarg :promoted-to
    :type string
    :accessor promoted-to)
   (requirements
    :initarg :requirements
    :type hash-table ;; string to bignum
    :initform (make-hash-table :test 'string=)
    :accessor requirements))
  (:documentation "TODO"))

(defclass func-pointer (vk-element)
  ((requirements
    :initarg :requirements
    :type string
    :accessor requirements))
  (:documentation "TODO"))

(defclass handle (vk-element)
  ((alias
    :initarg :alias
    :type string
    :accessor alias)
   (children
    :initarg :children
    :type list ;; string
    :accessor children)
   (parents
    :initarg :parents
    :type list ;; string
    :accessor parents)
   (commands
    :initarg :commands
    :type list ;; string
    :accessor commands)
   (delete-command
    :initarg :delete-command
    :type string
    :accessor delete-command)
   (delete-pool
    :initarg :delete-pool
    :type string
    :accessor delete-pool))
  (:documentation "TODO

See CHILDREN         The names of the HANDLE types that belong to this type.
See PARENTS          The names of the HANDLE types this type belongs to.
See COMMANDS         The names of the COMMAND types that are performed using
                     this type.
See DELETE-COMMAND   The name of the command that deletes this handle.
See DELETE-POOL
"))

(defclass member-data (vk-element has-type-info has-array-sizes)
  ((bit-count
    :initarg :bit-count
    :type string
    :accessor bit-count)
   (len
    :initarg :len
    :type list ;; string
    :accessor len)
   (no-autovalidity-p
    :initarg :no-autovalidity-p
    :type boolean
    :initform nil
    :accessor no-autovalidity-p)
   (optional-p
    :initarg :optional-p
    :type boolean
    :initform nil
    :accessor optional-p)
   (selection
    :initarg :selection
    :type string
    :accessor selection)
   (selector
    :initarg :selector
    :type string
    :accessor selector)
   (member-values
    :initarg :member-values
    :type list ;; string
    :accessor member-values)
   (used-constant
    :initarg :used-constant
    :type string
    :accessor used-constant))
  (:documentation "TODO"))

(defclass platform (vk-element)
  ((protect
    :initarg :protect
    :type string
    :accessor protect))
  (:documentation "TODO"))

(defclass structure (vk-element)
  ((allow-duplicate-p
    :initarg :allow-duplicate-p
    :type boolean
    :initform nil
    :accessor allow-duplicate-p)
   (is-union-p
    :initarg :is-union-p
    :type boolean
    :initarg nil
    :accessor is-union-p)
   (returned-only-p
    :initarg :returned-only-p
    :type boolean
    :initarg nil
    :accessor returned-only-p)
   (members
    :initarg :members
    :type list ;; member
    :accessor members)
   (struct-extends
    :initarg :struct-extends
    :type list ;; string
    :accessor struct-extends)
   (aliases
    :initarg :aliases
    :type list ;; string
    :accessor aliases)
   (sub-struct
    :initarg :sub-struct
    :type string
    :accessor sub-struct))
  (:documentation "TODO"))

(deftype type-category ()
  '(member
    :bitmask
    :basetype
    :define
    :enum
    :funcpointer
    :handle
    :requires
    :struct
    :union
    :unknown)
  "TODO: documentation")

(defclass vk-type (vk-element has-extensions has-feature)
  ((category
    :initarg :category
    :type type-category
    :accessor category))
  (:documentation "TODO"))

(defclass vulkan-spec ()
  ((base-types
    :initarg :base-types
    :type hash-table ;; string to base-type
    :initform (make-hash-table :test 'string=)
    :accessor base-types)
   (bitmasks
    :initarg :bitmasks
    :type hash-table ;; string to bitmask
    :initform (make-hash-table :test 'string=)
    :accessor bitmasks)
   (commands
    :initarg :commands
    :type hash-table ;; string to command
    :initform (make-hash-table :test 'string=)
    :accessor commands)
   (constants
    :initarg :constants
    :type list ;; string
    :accessor constants)
   (defines
    :initarg :defines
    :type list
    :accessor defines)
   (enums
    :initarg :enums
    :type hash-table ;; string to enum
    :initform (make-hash-table :test 'string=)
    :accessor enums)
   (extended-structs
    :initarg :extended-structs
    :type list ;; string
    :accessor extended-structs)
   (extensions
    :initarg :extensions
    :type hash-table ;; string to extension
    :initform (make-hash-table :test 'string=)
    :accessor extensions)
   (features
    :initarg :features
    :type hash-table ;; string to string
    :initform (make-hash-table :test 'string=)
    :accessor features)
   (func-pointers
    :initarg :func-pointers
    :type hash-table ;; string to func-pointer
    :initform (make-hash-table :test 'string=)
    :accessor func-pointers)
   (handles
    :initarg :handles
    :type hash-table ;; string to handle
    :initform (make-hash-table :test 'string=)
    :accessor handles)
   (includes
    :initarg :includes
    :type list ;; string
    :accessor includes)
   (listed-types
    :initarg :listed-types
    :type list ;; string
    :accessor listed-types)
   (listing-types
    :initarg :listing-types
    :type list ;; string
    :accessor listing-types)
   (platforms
    :initarg :platforms
    :type hash-table ;; string to platform
    :initform (make-hash-table :test 'string=)
    :accessor platforms)
   (structure-aliases
    :initarg :structure-aliases
    :type hash-table ;; string to string
    :initform (make-hash-table :test 'string=)
    :accessor structure-aliases)
   (structures
    :initarg :structures
    :type hash-table ;; string to structure
    :initform (make-hash-table :test 'string=)
    :accessor structures)
   (tags
    :initarg :tags
    :type list ;; string
    :accessor tags)
   (types
    :initarg :types
    :type hash-table ;; string to category
    :initform (make-hash-table :test 'string=)
    :accessor types)
   (typesafe-check
    :initarg :typesafe-check
    :type string
    :accessor typesafe-check)
   (version
    :initarg :version
    :type string
    :accessor version)
   (vulkan-licence-header
    :initarg :vulkan-licence-header
    :type string
    :accessor vulkan-licence-header))
  (:documentation "Vulkan specification class based on VulkanHppGenerator"))

;; todo: aliases
;; todo: extensions
;; todo: pNext chains
;; todo: create docstrings for types
(defclass vk-spec ()
  ((version
    :initarg :version
    :reader version)
   (copyright
    :initarg :copyright
    :reader copyright)
   (vendor-ids
    :initarg :vendor-ids
    :initform (list)
    :accessor vendor-ids)
   (vk-api-version
    :initarg :vk-api-version
    :initform (list)
    :accessor vk-api-version)
   (api-constants
    :initarg :api-constants
    :initform (make-hash-table :test 'equal)
    :accessor api-constants)
   (types ;; todo: this is a list for legacy reasons, but should probably also be a hash table
    :initarg :types
    :initform (list)
    :accessor types)
   (bitfields
    :initarg :bitfields
    :initform (make-hash-table :test 'equal)
    :accessor bitfields)
   (enums
    :initarg :enums
    :initform (make-hash-table :test 'equal)
    :accessor enums)
   (structs
    :initarg :structs
    :initform (make-hash-table :test 'equal)
    :accessor structs)
   (functions
    :initarg :funcs
    :initform (make-hash-table :test 'equal)
    :accessor functions)
   (function-apis
    :initarg :function-apis
    :initform (make-hash-table :test 'equal)
    :accessor function-apis)
   (extension-names
    :initarg :extension-names
    :initform (make-hash-table :test 'equal)
    :accessor extension-names)
   (handle-types
    :initarg :handle-types
    :initform (make-hash-table :test 'equal)
    :accessor handle-types)
   (alias-names ;; todo: handle aliases
    :initarg :alia-names
    :initform (list)
    :accessor alias-names))
  (:documentation "Vulkan Specification"))