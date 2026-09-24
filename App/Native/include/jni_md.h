/*
 * jni_md.h for Darwin arm64 (the unix one from OpenJDK, trimmed). jni.h next to it is from JDK 21;
 * both are GPLv2 with the Classpath Exception.
 */
#ifndef _JAVASOFT_JNI_MD_H_
#define _JAVASOFT_JNI_MD_H_

#ifndef JNIEXPORT
  #define JNIEXPORT __attribute__((visibility("default")))
#endif
#define JNIIMPORT __attribute__((visibility("default")))
#define JNICALL

typedef int jint;
#ifdef _LP64
typedef long jlong;
#else
typedef long long jlong;
#endif
typedef signed char jbyte;

#endif /* !_JAVASOFT_JNI_MD_H_ */
