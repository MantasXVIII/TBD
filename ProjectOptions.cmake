include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(TBD_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(TBD_setup_options)
  option(TBD_ENABLE_HARDENING "Enable hardening" ON)
  option(TBD_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    TBD_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    TBD_ENABLE_HARDENING
    OFF)

  TBD_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR TBD_PACKAGING_MAINTAINER_MODE)
    option(TBD_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(TBD_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(TBD_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TBD_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TBD_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TBD_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(TBD_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(TBD_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TBD_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(TBD_ENABLE_IPO "Enable IPO/LTO" ON)
    option(TBD_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(TBD_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TBD_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(TBD_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(TBD_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TBD_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TBD_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TBD_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(TBD_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(TBD_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TBD_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      TBD_ENABLE_IPO
      TBD_WARNINGS_AS_ERRORS
      TBD_ENABLE_USER_LINKER
      TBD_ENABLE_SANITIZER_ADDRESS
      TBD_ENABLE_SANITIZER_LEAK
      TBD_ENABLE_SANITIZER_UNDEFINED
      TBD_ENABLE_SANITIZER_THREAD
      TBD_ENABLE_SANITIZER_MEMORY
      TBD_ENABLE_UNITY_BUILD
      TBD_ENABLE_CLANG_TIDY
      TBD_ENABLE_CPPCHECK
      TBD_ENABLE_COVERAGE
      TBD_ENABLE_PCH
      TBD_ENABLE_CACHE)
  endif()

  TBD_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (TBD_ENABLE_SANITIZER_ADDRESS OR TBD_ENABLE_SANITIZER_THREAD OR TBD_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(TBD_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(TBD_global_options)
  if(TBD_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    TBD_enable_ipo()
  endif()

  TBD_supports_sanitizers()

  if(TBD_ENABLE_HARDENING AND TBD_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TBD_ENABLE_SANITIZER_UNDEFINED
       OR TBD_ENABLE_SANITIZER_ADDRESS
       OR TBD_ENABLE_SANITIZER_THREAD
       OR TBD_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${TBD_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${TBD_ENABLE_SANITIZER_UNDEFINED}")
    TBD_enable_hardening(TBD_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(TBD_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(TBD_warnings INTERFACE)
  add_library(TBD_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  TBD_set_project_warnings(
    TBD_warnings
    ${TBD_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(TBD_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    TBD_configure_linker(TBD_options)
  endif()

  include(cmake/Sanitizers.cmake)
  TBD_enable_sanitizers(
    TBD_options
    ${TBD_ENABLE_SANITIZER_ADDRESS}
    ${TBD_ENABLE_SANITIZER_LEAK}
    ${TBD_ENABLE_SANITIZER_UNDEFINED}
    ${TBD_ENABLE_SANITIZER_THREAD}
    ${TBD_ENABLE_SANITIZER_MEMORY})

  set_target_properties(TBD_options PROPERTIES UNITY_BUILD ${TBD_ENABLE_UNITY_BUILD})

  if(TBD_ENABLE_PCH)
    target_precompile_headers(
      TBD_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(TBD_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    TBD_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(TBD_ENABLE_CLANG_TIDY)
    TBD_enable_clang_tidy(TBD_options ${TBD_WARNINGS_AS_ERRORS})
  endif()

  if(TBD_ENABLE_CPPCHECK)
    TBD_enable_cppcheck(${TBD_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(TBD_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    TBD_enable_coverage(TBD_options)
  endif()

  if(TBD_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(TBD_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(TBD_ENABLE_HARDENING AND NOT TBD_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TBD_ENABLE_SANITIZER_UNDEFINED
       OR TBD_ENABLE_SANITIZER_ADDRESS
       OR TBD_ENABLE_SANITIZER_THREAD
       OR TBD_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    TBD_enable_hardening(TBD_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
