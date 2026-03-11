// protect_android.c — JNI bridge for VpnService.protect(fd) on Android.
//
// When mihomo creates an outbound socket (to proxy servers, DNS, etc.),
// it must be "protected" so Android doesn't route it back through the
// VPN TUN interface (routing loop). VpnService.protect(fd) marks the
// socket to bypass VPN routing.

#ifdef __ANDROID__

#include <jni.h>
#include <stdlib.h>

static JavaVM*   g_vm            = NULL;
static jobject   g_vpnService    = NULL;
static jmethodID g_protectMethod = NULL;

// Called from Go (via exported JNI function) when VPN service starts.
void store_vpn_service(JNIEnv* env, jobject vpnService) {
    // Get JavaVM reference (needed to attach Go threads later)
    (*env)->GetJavaVM(env, &g_vm);

    // Store global reference to VpnService instance
    if (g_vpnService != NULL) {
        (*env)->DeleteGlobalRef(env, g_vpnService);
    }
    g_vpnService = (*env)->NewGlobalRef(env, vpnService);

    // Cache protect(int) method ID
    jclass cls = (*env)->GetObjectClass(env, vpnService);
    g_protectMethod = (*env)->GetMethodID(env, cls, "protect", "(I)Z");
    (*env)->DeleteLocalRef(env, cls);
}

// Called from Go (via DefaultSocketHook) for each outbound socket.
int protect_fd(int fd) {
    if (g_vm == NULL || g_vpnService == NULL || g_protectMethod == NULL) {
        return 0;
    }

    JNIEnv* env = NULL;
    int need_detach = 0;

    jint status = (*g_vm)->GetEnv(g_vm, (void**)&env, JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != JNI_OK) {
            return 0;
        }
        need_detach = 1;
    } else if (status != JNI_OK) {
        return 0;
    }

    jboolean ok = (*env)->CallBooleanMethod(env, g_vpnService, g_protectMethod, (jint)fd);

    if (need_detach) {
        (*g_vm)->DetachCurrentThread(g_vm);
    }

    return ok ? 1 : 0;
}

// Called from Go when VPN stops — release global reference.
void clear_vpn_service(JNIEnv* env) {
    if (g_vpnService != NULL) {
        (*env)->DeleteGlobalRef(env, g_vpnService);
        g_vpnService = NULL;
    }
    g_protectMethod = NULL;
}

// JNI entry point: called by YueLinkVpnService.nativeStartProtect(this)
JNIEXPORT void JNICALL
Java_com_yueto_yuelink_YueLinkVpnService_nativeStartProtect(
    JNIEnv* env, jclass clazz, jobject vpnService) {
    store_vpn_service(env, vpnService);
}

// JNI entry point: called by YueLinkVpnService.nativeStopProtect()
JNIEXPORT void JNICALL
Java_com_yueto_yuelink_YueLinkVpnService_nativeStopProtect(
    JNIEnv* env, jclass clazz) {
    clear_vpn_service(env);
}

#endif
