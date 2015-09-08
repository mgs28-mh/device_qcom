/*
 * Copyright (C) 2015 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#define LOG_TAG "FingerprintHal"

#include <errno.h>
#include <endian.h>
#include <inttypes.h>
#include <malloc.h>
#include <string.h>
#include <cutils/log.h>
#include <hardware/hardware.h>
#include <hardware/fingerprint.h>
#include <hardware/qemud.h>

#define FINGERPRINT_LISTEN_SERVICE_NAME "fingerprintlisten"
#define FINGERPRINT_FILENAME \
    "/data/system/users/0/fpdata/emulator_fingerprint_storage.bin"
#define MAX_COMM_CHARS 128
#define MAX_COMM_ERRORS 8
#define MAX_NUM_FINGERS 20
#define MAX_FID_VALUE 0x7FFFFFFF  // Arbitrary limit

typedef enum worker_state_t {
    STATE_IDLE = 0,
    STATE_ENROLL,
    STATE_SCAN,
    STATE_EXIT
} worker_state_t;

typedef struct worker_thread_t {
    pthread_t thread;
    worker_state_t state;
    uint64_t secureid[MAX_NUM_FINGERS];
    uint64_t authenid[MAX_NUM_FINGERS];
} worker_thread_t;

typedef struct qemu_fingerprint_device_t {
    fingerprint_device_t device;  // "inheritance"
    worker_thread_t listener;
    uint64_t op_id;
    uint64_t challenge;
    uint64_t user_id;
    uint64_t group_id;
    uint64_t secure_user_id;
    uint64_t authenticator_id;
    int qchanfd;
    pthread_mutex_t lock;
} qemu_fingerprint_device_t;

/******************************************************************************/

static void saveFingerprint(worker_thread_t* listener, int idx) {
    ALOGD("----------------> %s -----------------> idx %d", __FUNCTION__, idx);

    // Save fingerprints to file
    FILE* fp = fopen(FINGERPRINT_FILENAME, "r+");  // write but don't truncate
    if (fp == NULL) {
        ALOGE("Could not open fingerprints storage at %s; "
              "fingerprints won't be saved",
              FINGERPRINT_FILENAME);
        perror("Failed to open file");
        return;
    }

    ALOGD("Write fingerprint[%d] (0x%" PRIx64 ",0x%" PRIx64 ")", idx,
          listener->secureid[idx], listener->authenid[idx]);

    if (fseek(fp, (idx) * sizeof(uint64_t), SEEK_SET) < 0) {
        ALOGE("Failed while seeking for fingerprint[%d] in emulator storage",
              idx);
        fclose(fp);
        return;
    }
    int ns = fwrite(&listener->secureid[idx], sizeof(uint64_t), 1, fp);
    if (fseek(fp, (MAX_NUM_FINGERS + idx) * sizeof(uint64_t), SEEK_SET) < 0) {
        ALOGE("Failed while seeking for fingerprint[%d] in emulator storage",
              idx);
        fclose(fp);
        return;
    }
    int na = fwrite(&listener->authenid[idx], sizeof(uint64_t), 1, fp);
    if (ns != 1 || na != 1)
        ALOGW("Corrupt emulator fingerprints storage; could not save "
              "fingerprints");

    fclose(fp);

    return;
}

static void loadFingerprints(worker_thread_t* listener) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    FILE* fp = fopen(FINGERPRINT_FILENAME, "a+");  // so we can create if empty
    if (fp == NULL) {
        ALOGE("Could not load fingerprints from storage at %s; "
              "it has not yet been created.",
              FINGERPRINT_FILENAME);
        perror("Failed to open/create file");
        return;
    }

    int ns = fread(listener->secureid, MAX_NUM_FINGERS * sizeof(uint64_t), 1,
                   fp);
    int na = fread(listener->authenid, MAX_NUM_FINGERS * sizeof(uint64_t), 1,
                   fp);
    if (ns != 1 || na != 1)
        ALOGW("Corrupt emulator fingerprints storage (read %d+%db)", ns, na);

    int i = 0;
    for (i = 0; i < MAX_NUM_FINGERS; i++)
        ALOGD("Read fingerprint %d (0x%" PRIx64 ",0x%" PRIx64 ")", i,
              listener->secureid[i], listener->authenid[i]);

    fclose(fp);

    return;
}

/******************************************************************************/

static uint64_t get_64bit_rand() {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    uint64_t r = (((uint64_t)rand()) << 32) | ((uint64_t)rand());
    return r != 0 ? r : 1;
}

static uint64_t fingerprint_get_auth_id(struct fingerprint_device* device) {
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    uint64_t authenticator_id = 0;
    pthread_mutex_lock(&qdev->lock);
    authenticator_id = qdev->authenticator_id;
    pthread_mutex_unlock(&qdev->lock);

    return authenticator_id;
}

static int fingerprint_set_active_group(struct fingerprint_device __unused *device, uint32_t gid,
        const char *path) {
    ALOGW("Setting active finger group not implemented");
    return 0;
}

static int fingerprint_authenticate(struct fingerprint_device *device,
    uint64_t operation_id, __unused uint32_t gid)
{
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;

    pthread_mutex_lock(&qdev->lock);
    qdev->op_id = operation_id;
    qdev->listener.state = STATE_SCAN;
    pthread_mutex_unlock(&qdev->lock);

    return 0;
}

static int fingerprint_enroll(struct fingerprint_device *device,
        const hw_auth_token_t *hat,
        uint32_t __unused gid,
        uint32_t __unused timeout_sec) {
    ALOGD("fingerprint_enroll");
    qemu_fingerprint_device_t* dev = (qemu_fingerprint_device_t*)device;
    if (!hat) {
        ALOGW("%s: null auth token", __func__);
        return -EPROTONOSUPPORT;
    }
    if (hat->challenge == dev->challenge) {
        dev->secure_user_id = hat->user_id;
    } else {
        ALOGW("%s: invalid auth token", __func__);
    }

    if (hat->version != HW_AUTH_TOKEN_VERSION) {
        return -EPROTONOSUPPORT;
    }
    if (hat->challenge != dev->challenge && !(hat->authenticator_type & HW_AUTH_FINGERPRINT)) {
        return -EPERM;
    }

    dev->user_id = hat->user_id;

    pthread_mutex_lock(&dev->lock);
    dev->listener.state = STATE_ENROLL;
    pthread_mutex_unlock(&dev->lock);

    // fingerprint id, authenticator id, and secure_user_id
    // will be stored by worked thread

    return 0;

}

static uint64_t fingerprint_pre_enroll(struct fingerprint_device *device) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    uint64_t challenge = 0;
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;

    challenge = get_64bit_rand();

    pthread_mutex_lock(&qdev->lock);
    qdev->challenge = challenge;
    pthread_mutex_unlock(&qdev->lock);

    return challenge;
}

static int fingerprint_post_enroll(struct fingerprint_device* device) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;

    pthread_mutex_lock(&qdev->lock);
    qdev->challenge = 0;
    pthread_mutex_unlock(&qdev->lock);

    return 0;
}

static int fingerprint_cancel(struct fingerprint_device *device) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;

    fingerprint_msg_t msg = {0};
    msg.type = FINGERPRINT_ERROR;
    msg.data.error = FINGERPRINT_ERROR_CANCELED;

    pthread_mutex_lock(&qdev->lock);
    qdev->listener.state = STATE_IDLE;
    pthread_mutex_unlock(&qdev->lock);

    device->notify(&msg);

    return 0;
}

static int fingerprint_enumerate(struct fingerprint_device *device,
        fingerprint_finger_id_t *results, uint32_t *max_size) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    if (device == NULL || results == NULL || max_size == NULL) {
        ALOGE("Cannot enumerate saved fingerprints with uninitialized params");
        return -1;
    }

    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;
    unsigned int i = 0;
    int num = 0;
    for (i = 0; i < MAX_NUM_FINGERS; i++) {
        if (qdev->listener.secureid[i] != 0 ||
            qdev->listener.authenid[i] != 0) {
            ALOGD("ENUM: Fingerprint [%d] = 0x%" PRIx64 ",%" PRIx64, i,
                  qdev->listener.secureid[i], qdev->listener.authenid[i]);
            num++;
        }
    }

    return num;
}

static int fingerprint_remove(struct fingerprint_device *device,
        uint32_t __unused gid, uint32_t fid) {
    int idx = 0;
    fingerprint_msg_t msg = {0};
    ALOGD("----------------> %s -----------------> fid %d", __FUNCTION__, fid);
    if (device == NULL) {
        ALOGE("Can't remove fingerprint (gid=%d, fid=%d); "
              "device not initialized properly",
              gid, fid);
        return -1;
    }

    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;

    if (fid == 0) {
        // Delete all fingerprints
        // I'll do this one at a time, so I am not
        // holding the mutext during the notification
        bool listIsEmpty;
        do {
            pthread_mutex_lock(&qdev->lock);
            listIsEmpty = true;  // Haven't seen a valid entry yet
            for (idx = 0; idx < MAX_NUM_FINGERS; idx++) {
                uint32_t theFid = qdev->listener.authenid[idx];
                if (theFid != 0) {
                    // Delete this entry
                    qdev->listener.secureid[idx] = 0;
                    qdev->listener.authenid[idx] = 0;
                    saveFingerprint(&qdev->listener, idx);

                    // Send a notification that we deleted this one
                    pthread_mutex_unlock(&qdev->lock);
                    msg.type = FINGERPRINT_TEMPLATE_REMOVED;
                    msg.data.removed.finger.fid = theFid;
                    device->notify(&msg);

                    // Because we released the mutex, the list
                    // may have changed. Restart the 'for' loop
                    // after reacquiring the mutex.
                    listIsEmpty = false;
                    break;
                }
            }  // end for (idx < MAX_NUM_FINGERS)
        } while (!listIsEmpty);
        qdev->listener.state = STATE_IDLE;
        pthread_mutex_unlock(&qdev->lock);
    } else {
        // Delete one fingerprint
        // Look for this finger ID in our table.
        pthread_mutex_lock(&qdev->lock);
        for (idx = 0; idx < MAX_NUM_FINGERS; idx++) {
            if (qdev->listener.authenid[idx] == fid &&
                qdev->listener.secureid[idx] != 0) {
                // Found it!
                break;
            }
        }
        if (idx >= MAX_NUM_FINGERS) {
            qdev->listener.state = STATE_IDLE;
            pthread_mutex_unlock(&qdev->lock);
            ALOGE("Fingerprint ID %d not found", fid);
            return FINGERPRINT_ERROR;
        }

        qdev->listener.secureid[idx] = 0;
        qdev->listener.authenid[idx] = 0;
        saveFingerprint(&qdev->listener, idx);

        qdev->listener.state = STATE_IDLE;
        pthread_mutex_unlock(&qdev->lock);

        msg.type = FINGERPRINT_TEMPLATE_REMOVED;
        msg.data.removed.finger.fid = fid;
        device->notify(&msg);
    }

    return 0;
}

static int set_notify_callback(struct fingerprint_device *device,
                               fingerprint_notify_t notify) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    if (device == NULL || notify == NULL) {
        ALOGE("Failed to set notify callback @ %p for fingerprint device %p",
              device, notify);
        return -1;
    }

    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;
    pthread_mutex_lock(&qdev->lock);
    qdev->listener.state = STATE_IDLE;
    device->notify = notify;
    pthread_mutex_unlock(&qdev->lock);
    ALOGD("fingerprint callback notification set");

    return 0;
}

static void send_scan_notice(qemu_fingerprint_device_t* qdev, int fid) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);

    // acquired message
    fingerprint_msg_t acqu_msg = {0};
    acqu_msg.type = FINGERPRINT_ACQUIRED;
    acqu_msg.data.acquired.acquired_info = FINGERPRINT_ACQUIRED_GOOD;

    // authenticated message
    fingerprint_msg_t auth_msg = {0};
    auth_msg.type = FINGERPRINT_AUTHENTICATED;
    auth_msg.data.authenticated.finger.fid = fid;
    auth_msg.data.authenticated.finger.gid = 0;  // unused
    auth_msg.data.authenticated.hat.version = HW_AUTH_TOKEN_VERSION;
    auth_msg.data.authenticated.hat.authenticator_type =
            htobe32(HW_AUTH_FINGERPRINT);
    auth_msg.data.authenticated.hat.challenge = qdev->op_id;
    auth_msg.data.authenticated.hat.authenticator_id = qdev->authenticator_id;
    auth_msg.data.authenticated.hat.user_id = qdev->secure_user_id;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    auth_msg.data.authenticated.hat.timestamp =
            htobe64((uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);

    //  pthread_mutex_lock(&qdev->lock);
    qdev->device.notify(&acqu_msg);
    qdev->device.notify(&auth_msg);
    //  pthread_mutex_unlock(&qdev->lock);

    return;
}

static void send_enroll_notice(qemu_fingerprint_device_t* qdev, int fid) {
    ALOGD("----------------> %s -----------------> fid %d", __FUNCTION__, fid);

    if (fid == 0) {
        ALOGD("Fingerprint ID is zero (invalid)");
        return;
    }
    if (qdev->secure_user_id == 0) {
        ALOGD("Secure user ID is zero (invalid)");
        return;
    }

    // Find an available entry in the table
    pthread_mutex_lock(&qdev->lock);
    int idx = 0;
    for (idx = 0; idx < MAX_NUM_FINGERS; idx++) {
        if (qdev->listener.secureid[idx] == 0 ||
            qdev->listener.authenid[idx] == 0) {
            // This entry is available
            break;
        }
    }
    if (idx >= MAX_NUM_FINGERS) {
        qdev->listener.state = STATE_SCAN;
        pthread_mutex_unlock(&qdev->lock);
        ALOGD("Fingerprint ID table is full");
        return;
    }

    qdev->listener.secureid[idx] = qdev->secure_user_id;
    qdev->listener.authenid[idx] = fid;
    saveFingerprint(&qdev->listener, idx);

    qdev->listener.state = STATE_SCAN;
    pthread_mutex_unlock(&qdev->lock);

    // LOCKED notification?
    fingerprint_msg_t msg = {0};
    msg.type = FINGERPRINT_TEMPLATE_ENROLLING;
    msg.data.enroll.finger.fid = fid;
    msg.data.enroll.samples_remaining = 0;
    qdev->device.notify(&msg);

    return;
}

static worker_state_t getListenerState(qemu_fingerprint_device_t* dev) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    worker_state_t state = STATE_IDLE;

    pthread_mutex_lock(&dev->lock);
    state = dev->listener.state;
    pthread_mutex_unlock(&dev->lock);

    return state;
}

static void* listenerFunction(void* data) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)data;

    pthread_mutex_lock(&qdev->lock);
    qdev->qchanfd = qemud_channel_open(FINGERPRINT_LISTEN_SERVICE_NAME);
    if (qdev->qchanfd < 0) {
        ALOGE("listener cannot open fingerprint listener service exit");
        pthread_mutex_unlock(&qdev->lock);
        return NULL;
    }
    qdev->listener.state = STATE_IDLE;
    pthread_mutex_unlock(&qdev->lock);

    const char* cmd = "listen";
    if (qemud_channel_send(qdev->qchanfd, cmd, strlen(cmd)) < 0) {
        ALOGE("cannot write fingerprint 'listen' to host");
        return NULL;
    }
    int comm_errors = 0;
    while (getListenerState(qdev) != STATE_EXIT) {
        int size = 0;
        int fid = 0;
        char buffer[MAX_COMM_CHARS] = {0};
        // will block until a new event happens
        if ((size = qemud_channel_recv(qdev->qchanfd, buffer,
                                       sizeof(buffer) - 1)) > 0) {
            buffer[size] = '\0';
            if (sscanf(buffer, "on:%d", &fid) == 1) {
                if (fid > 0 && fid <= MAX_FID_VALUE) {
                    switch (qdev->listener.state) {
                        case STATE_ENROLL:
                            send_enroll_notice(qdev, fid);
                            break;
                        case STATE_SCAN:
                            send_scan_notice(qdev, fid);
                            break;
                        default:
                            ALOGE("fingerprint event listener at unexpected "
                                  "state 0%x",
                                  qdev->listener.state);
                    }
                } else {
                    ALOGE("fingerprintid %d not in valid range [%d, %d] and "
                          "will be "
                          "ignored",
                          fid, 1, MAX_FID_VALUE);
                    continue;
                }
            } else if (strncmp("off", buffer, 3) == 0) {
                // TODO: Nothing to do here ? Looks valid
                ALOGD("fingerprint ID %d off", fid);
            } else {
                ALOGE("Invalid command '%s' to fingerprint listener", buffer);
            }
        } else {
            ALOGE("fingerprint listener receive failure");
            if (comm_errors > MAX_COMM_ERRORS)
                break;
        }
    }

    ALOGD("Listener exit with %d receive errors", comm_errors);
    return NULL;
}

static int fingerprint_close(hw_device_t* device) {
    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    if (device == NULL) {
        ALOGE("fingerprint hw device is NULL");
        return -1;
    }

    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)device;
    pthread_mutex_lock(&qdev->lock);
    if (qdev->qchanfd != 0)
        close(qdev->qchanfd);  // unblock listener
    qdev->listener.state = STATE_EXIT;
    pthread_mutex_unlock(&qdev->lock);

    pthread_join(qdev->listener.thread, NULL);
    pthread_mutex_destroy(&qdev->lock);
    free(qdev);

    return 0;
}

static int fingerprint_open(const hw_module_t* module, const char __unused *id,
                            hw_device_t** device)
{

    ALOGD("----------------> %s ----------------->", __FUNCTION__);
    if (device == NULL) {
        ALOGE("NULL device on open");
        return -EINVAL;
    }

    qemu_fingerprint_device_t* qdev = (qemu_fingerprint_device_t*)calloc(
            1, sizeof(qemu_fingerprint_device_t));
    if (qdev == NULL) {
        ALOGE("Insufficient memory for virtual fingerprint device");
        return -ENOMEM;
    }

    loadFingerprints(&qdev->listener);

    qdev->device.common.tag = HARDWARE_DEVICE_TAG;
    qdev->device.common.version = HARDWARE_MODULE_API_VERSION(2, 0);
    qdev->device.common.module = (struct hw_module_t*)module;
    qdev->device.common.close = fingerprint_close;

    qdev->device.pre_enroll = fingerprint_pre_enroll;
    qdev->device.enroll = fingerprint_enroll;
    qdev->device.post_enroll = fingerprint_post_enroll;
    qdev->device.get_authenticator_id = fingerprint_get_auth_id;
    qdev->device.set_active_group = fingerprint_set_active_group;
    qdev->device.authenticate = fingerprint_authenticate;
    qdev->device.cancel = fingerprint_cancel;
    qdev->device.enumerate = fingerprint_enumerate;
    qdev->device.remove = fingerprint_remove;
    qdev->device.set_notify = set_notify_callback;
    qdev->device.notify = NULL;

    // init and create listener thread
    pthread_mutex_init(&qdev->lock, NULL);
    if (pthread_create(&qdev->listener.thread, NULL, listenerFunction, qdev) !=
        0)
        return -1;

    // "Inheritance" / casting
    *device = &qdev->device.common;

    return 0;
}

static struct hw_module_methods_t fingerprint_module_methods = {
    .open = fingerprint_open,
};

fingerprint_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag                = HARDWARE_MODULE_TAG,
        .module_api_version = FINGERPRINT_MODULE_API_VERSION_2_0,
        .hal_api_version    = HARDWARE_HAL_API_VERSION,
        .id                 = FINGERPRINT_HARDWARE_MODULE_ID,
        .name               = "Emulator Fingerprint HAL",
        .author             = "The Android Open Source Project",
        .methods            = &fingerprint_module_methods,
    },
};
