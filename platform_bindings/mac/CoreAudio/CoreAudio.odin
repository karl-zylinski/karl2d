#+build darwin
package CoreAudio

StreamBasicDescription :: struct {
	mSampleRate:       f64,
	mFormatID:         FormatID,
	mFormatFlags:      FormatFlags,
	mBytesPerPacket:   u32,
	mFramesPerPacket:  u32,
	mBytesPerFrame:    u32,
	mChannelsPerFrame: u32,
	mBitsPerChannel:   u32,
	mReserved:         u32,
}

FormatID :: enum u32 {
	LinearPCM = 1819304813,
}

FormatFlag :: enum u32 {
	IsFloat  = 0,
	IsPacked = 3,
}
FormatFlags :: bit_set[FormatFlag; u32]

StreamPacketDescription :: struct {
	mStartOffset:            i64,
	mVariableFramesInPacket: u32,
	mDataByteSize:           u32,
}

SMPTETime :: struct {
	mSubframes:       i16,
	mSubframeDivisor: i16,
	mCounter:         u32,
	mType:            u32,
	mFlags:           u32,
	mHours:           i16,
	mMinutes:         i16,
	mSeconds:         i16,
	mFrames:          i16,
}

TimeStamp :: struct {
	mSampleTime:    f64,
	mHostTime:      u64,
	mRateScalar:    f64,
	mWordClockTime: u64,
	mSMPTETime:     SMPTETime,
	mFlags:         u32,
	mReserved:      u32,
}
