Change Log
==========


1.1.0
-----------------------
### Enhancements:

* Dynamic frameworks can now be processed.
* Add git commit hash to version number.

### Changes:

* New identifiers will typically be eight characters long, regardless of their original length, to help prevent conflicts.


1.0.1
-----------------------
### Enhancements:

* Now supports macOS Sierra and Xcode 8.
* Updated documentation.


1.0
-----------------------
### Functional Changes:

* Forked from [Polidea iOS Class Guard](https://github.com/Polidea/ios-class-guard), and renamed the project and program.
* Fixed corruption in git repository, see details below.
* Improved usability of the application:
    * Split the obfuscation process into two phases (analyze and obfuscate-sources).
    * Documented how to use the application with any version control system and without use of a wrapper script.
    * Documented how to integrate the obfuscation process into an existing Xcode project.
    * Added protection against "double obfuscation".
* Streamlined use of the application for supported platforms: iOS apps on Xcode 7.
* Changed crash dump translation to require an output file name.
* Removed exclusion propagation for excluded symbols (-x).

### Enhancements:

* Simplified program options and mnemonics, and enforced single mode selection.
* Added support for category exclusion via class filters.
* Updated the list of explicitly excluded symbols.
* Improved the documentation.
* Clarified the usage text.
* Verified support with PPiOS-ControlFlow.
* Cleaned up the source tree, removing unnecessary and derived files.
* Added integration tests.

### Fixes:

* Removed chaining of class filters, which was essentially broken since its behavior depended on the arbitrary order in which classes were processed.
* Fixed command-line argument validation.
* Fixed support for applications targeting iPhoneOS, broken by the release of Xcode 7, and verified support for Xcode 7.3.

### Additional Details

Original commit [509591f](https://github.com/Polidea/ios-class-guard/commit/509591f78f37905913ba0cbd832e5e4f7b925a8a) was corrupted. This was fixed by modifying it and rewriting the commit history after it. The new repaired commit is 496ae586. The fork point in the new history is 94121d10.
