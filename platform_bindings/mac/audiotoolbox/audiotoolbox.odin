#+build darwin

package karl2d_darwin_audiotoolbox

foreign import AudioToolbox "system:AudioToolbox.framework"

OSStatus :: distinct i32

Audio_Queue_Error :: enum i32 {
	NoErr                  = 0,
	Invalid_Buffer         = -66687,
	Buffer_Empty           = -66686,
	Disposal_Pending       = -66685,
	Invalid_Property       = -66684,
	Invalid_Property_Size  = -66683,
	Invalid_Parameter      = -66682,
	Cannot_Start           = -66681,
	Invalid_Device         = -66680,
	Buffer_In_Queue        = -66679,
	Invalid_Run_State      = -66678,
	Invalid_Queue_Type     = -66677,
	Permissions            = -66676,
	Invalid_Property_Value = -66675,
	Prime_Timed_Out        = -66674,
	Codec_Not_Found        = -66673,
	Invalid_Codec_Access   = -66672,
	Queue_Invalidated      = -66671,
	Too_Many_Taps          = -66670,
	Invalid_Tap_Context    = -66669,
	Record_Underrun        = -66668,
	Invalid_Tap_Type       = -66667,
	Buffer_Enqueued_Twice  = -66666,
	Enqueue_During_Reset   = -66632,
	Invalid_Offline_Mode   = -66626,
}

Audio_Format_ID :: enum u32 {
	Linear_PCM = 0x6C70636D, // 'lpcm'
}

PCM_Flag :: enum u32 {
	Is_Float           = 0,
	Is_Big_Endian      = 1,
	Is_Signed_Integer  = 2,
	Is_Packed          = 3,
	Is_Aligned_High    = 4,
	Is_Non_Interleaved = 5,
	Is_Non_Mixable     = 6,
}
PCM_Flags :: bit_set[PCM_Flag;u32]

Audio_Timestamp_Flag :: enum u32 {
	Sample_Time_Valid     = 0,
	Host_Time_Valid       = 1,
	Rate_Scalar_Valid     = 2,
	Word_Clock_Time_Valid = 3,
	SMPTE_Time_Valid      = 4,
}
Audio_Timestamp_Flags :: bit_set[Audio_Timestamp_Flag;u32]

Audio_Queue_Property :: enum u32 {
	Is_Running = 0x6171726E, // 'aqrn'
}

AudioStreamBasicDescription :: struct {
	mSampleRate:       f64,
	mFormatID:         Audio_Format_ID,
	mFormatFlags:      PCM_Flags,
	mBytesPerPacket:   u32,
	mFramesPerPacket:  u32,
	mBytesPerFrame:    u32,
	mChannelsPerFrame: u32,
	mBitsPerChannel:   u32,
	mReserved:         u32,
}

AudioQueueRef :: distinct rawptr

AudioQueueBuffer :: struct {
	mAudioDataBytesCapacity:            u32,
	mAudioData:                         rawptr,
	mAudioDataByteSize:                 u32,
	mUserData:                          rawptr,
	mPacketDescriptionCapacity:         u32,
	mPacketDescriptions:                rawptr,
	mPacketDescriptionCount:            u32,
	mReserved1, mReserved2, mReserved3: u32,
}

AudioQueueBufferRef :: ^AudioQueueBuffer

AudioQueueOutputCallback :: #type proc "c" (
	inUserData: rawptr,
	inAQ: AudioQueueRef,
	inBuffer: AudioQueueBufferRef,
)

AudioQueueTimelineRef :: distinct rawptr

SMPTETime :: struct {
	mSubframes:                          i16,
	mSubframeDivisor:                    i16,
	mCounter:                            u32,
	mType:                               u32,
	mFlags:                              u32,
	mHours, mMinutes, mSeconds, mFrames: i16,
}

AudioTimeStamp :: struct {
	mSampleTime:    f64,
	mHostTime:      u64,
	mRateScalar:    f64,
	mWordClockTime: u64,
	mSMPTETime:     SMPTETime,
	mFlags:         Audio_Timestamp_Flags,
	mReserved:      u32,
}

@(default_calling_convention = "c")
foreign AudioToolbox {
	AudioQueueNewOutput :: proc(inFormat: ^AudioStreamBasicDescription, inCallbackProc: AudioQueueOutputCallback, inUserData: rawptr, inCallbackRunLoop: rawptr, inCallbackRunLoopMode: rawptr, inFlags: u32, outAQ: ^AudioQueueRef) -> Audio_Queue_Error ---
	AudioQueueDispose :: proc(inAQ: AudioQueueRef, inImmediate: bool) -> Audio_Queue_Error ---
	AudioQueueAllocateBuffer :: proc(inAQ: AudioQueueRef, inBufferByteSize: u32, outBuffer: ^AudioQueueBufferRef) -> Audio_Queue_Error ---
	AudioQueueFreeBuffer :: proc(inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) -> Audio_Queue_Error ---
	AudioQueueEnqueueBuffer :: proc(inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef, inNumPacketDescs: u32, inPacketDescs: rawptr) -> Audio_Queue_Error ---
	AudioQueueStart :: proc(inAQ: AudioQueueRef, inStartTime: ^AudioTimeStamp) -> Audio_Queue_Error ---
	AudioQueueStop :: proc(inAQ: AudioQueueRef, inImmediate: bool) -> Audio_Queue_Error ---
	AudioQueuePause :: proc(inAQ: AudioQueueRef) -> Audio_Queue_Error ---
	AudioQueueGetProperty :: proc(inAQ: AudioQueueRef, inID: Audio_Queue_Property, outData: rawptr, ioDataSize: ^u32) -> Audio_Queue_Error ---
	AudioQueueSetProperty :: proc(inAQ: AudioQueueRef, inID: Audio_Queue_Property, inData: rawptr, inDataSize: u32) -> Audio_Queue_Error ---
	AudioQueueCreateTimeline :: proc(inAQ: AudioQueueRef, outTimeline: ^AudioQueueTimelineRef) -> Audio_Queue_Error ---
	AudioQueueDisposeTimeline :: proc(inAQ: AudioQueueRef, inTimeline: AudioQueueTimelineRef) -> Audio_Queue_Error ---
	AudioQueueGetCurrentTime :: proc(inAQ: AudioQueueRef, inTimeline: AudioQueueTimelineRef, outTimeStamp: ^AudioTimeStamp, outTimelineDiscontinuity: ^bool) -> Audio_Queue_Error ---
}
