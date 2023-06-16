#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#include <mach/mach_time.h>
#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventData.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"
#include "headers/IOHIDEventSystem.h"

#define PORT 6000
#define ADDR "0.0.0.0"

#define TASK_PERFORM_TOUCH 10
#define TASK_PROCESS_BRING_FOREGROUND 11
#define TASK_SHOW_ALERT_BOX 12
#define TASK_RUN_SHELL 13
#define TASK_TOUCH_RECORDING_START 14
#define TASK_TOUCH_RECORDING_STOP 15
#define TASK_CRAZY_TAP 16
#define TASK_DEPRICATED 17
#define TASK_USLEEP 18
#define TASK_PLAY_SCRIPT 19
#define TASK_PLAY_SCRIPT_FORCE_STOP 20
#define TASK_PRESS_HOME_BUTTON 29
#define TASK_PRESS_POWER_BUTTON 30
#define TASK_TAKE_SCREENSHOT 31

#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2

// @interface SpringBoard ()
// // @property(readonly, nonatomic) SBHomeHardwareButton *homeHardwareButton;
// - (void)_menuButtonDown;
// - (void)_menuButtonUp;
// @end

static CGFloat device_screen_width = 0;
static CGFloat device_screen_height = 0;

const int TOUCH_DATA_LEN = 13;

// touch event sender id
unsigned long long int senderID = 0x0;

IOHIDEventSystemClientRef ioHIDEventSystemForSenderID = NULL;

//socket stuff
CFSocketRef socketRef;
CFWriteStreamRef writeStreamRef = NULL;
CFReadStreamRef readStreamRef = NULL;

OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);

static NSMutableDictionary *socketClients = NULL; //maps a write stream to a read stream

// void showAlertBoxFromRawData(UInt8 *eventData)
// {
//     NSString *alertData = [NSString stringWithFormat:@"%s", eventData];
//     NSArray *alertDataArray = [alertData componentsSeparatedByString:@";;"];
//     showAlertBox(alertDataArray[0], alertDataArray[1], 999);
// }

void showAlertBox(NSString* title, NSString* content, int dismissTime)
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    [dict setObject: title forKey: (__bridge NSString*)kCFUserNotificationAlertHeaderKey];
    [dict setObject: content forKey: (__bridge NSString*)kCFUserNotificationAlertMessageKey];
    [dict setObject: @"Ok" forKey:(__bridge NSString*)kCFUserNotificationDefaultButtonTitleKey];
    
    SInt32 error = 0;
    CFUserNotificationRef alert = CFUserNotificationCreate(NULL, 0, kCFUserNotificationPlainAlertLevel, &error, (__bridge CFDictionaryRef)dict);


    
    CFOptionFlags response;
    
     if((error) || (CFUserNotificationReceiveResponse(alert, dismissTime, &response))) {
        NSLog(@"com.zjx.springboard: alert error or no user response after %d seconds for title: %@. Content %@", dismissTime, title, content);
     }
    
    /*
    else if((response & 0x3) == kCFUserNotificationAlternateResponse) {
        NSLog(@"cancel");
    } else if((response & 0x3) == kCFUserNotificationDefaultResponse) {
        NSLog(@"view");
    }
    */

    CFRelease(alert);
}

static void setSenderIdCallback(void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event)
{
	//check if the the type of the IO HID event was a digitizer event
    if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer){
		if (senderID == 0)
        {
			//not sure what senderID does yet, but this sets it be from the one that sent the vent
			senderID = IOHIDEventGetSenderID(event);
            NSLog(@"### com.zjx.springboard: sender id is: %qX", senderID);
        }
		//i think this i a temprorary thing to only allow one command at once, but we will see
        if (ioHIDEventSystemForSenderID) // unregister the callback
        {
            IOHIDEventSystemClientUnregisterEventCallback(ioHIDEventSystemForSenderID);
            IOHIDEventSystemClientUnscheduleWithRunLoop(ioHIDEventSystemForSenderID, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            ioHIDEventSystemForSenderID = NULL;
        }
    }
}


//The following creates a variable to hold IO HID, then stores every IO HID in the main loop to that variable
//and then for every IO HID event stored in that variable it calls setSenderIdCallback() to decide what to do
void startSetSenderIDCallBack()
{
	//Creates a variable that will hold IO HID events
    ioHIDEventSystemForSenderID = IOHIDEventSystemClientCreate(kCFAllocatorDefault);

	//Makes it so that every IO HID event on the main loop gets saved to the variable created above
    IOHIDEventSystemClientScheduleWithRunLoop(ioHIDEventSystemForSenderID, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

	//For every IO HID event that was captured in the variable, call the function in the second paremeter to decide what to do
    IOHIDEventSystemClientRegisterEventCallback(ioHIDEventSystemForSenderID, (IOHIDEventSystemClientEventCallback)setSenderIdCallback, NULL, NULL);
    //NSLog(@"### com.zjx.springboard: screen width: %f, screen height: %f", device_screen_width, device_screen_height);
}

static int getTouchCountFromDataArray(UInt8* dataArray)
{
	int count = (dataArray[0] - '0');
	return count;
}

static int getTouchTypeFromDataArray(UInt8* dataArray, int index)
{
	int type = (dataArray[1+index*TOUCH_DATA_LEN] - '0');
	return type;
}

static int getTouchIndexFromDataArray(UInt8* dataArray, int index)
{
	int touchIndex = 0;
	for (int i = 2; i <= 3; i++)
	{
		touchIndex += (dataArray[i+index*TOUCH_DATA_LEN] - '0')*pow(10, 3-i);
	}
	return touchIndex;
}

static float getTouchXFromDataArray(UInt8* dataArray, int index)
{
	int x = 0;
	for (int i = 4; i <= 8; i++)
	{
		x += (dataArray[i+index*TOUCH_DATA_LEN] - '0')*pow(10, 8-i);
	}
	return x/10.0;
}

static float getTouchYFromDataArray(UInt8* dataArray, int index)
{
	int y = 0;
	for (int i = 9; i <= 13; i++)
	{
		y += (dataArray[i+index*TOUCH_DATA_LEN] - '0')*pow(10, 13-i);
	}
	return y/10.0;
}


static IOHIDEventRef generateChildEventTouchDown(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 2, 35, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 1, 1, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index getRandomNumberFloat(0.03, 0.05)
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}


static IOHIDEventRef generateChildEventTouchMove(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 2, 4, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 1, 1, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}


static IOHIDEventRef generateChildEventTouchUp(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 2, 33, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 0, 0, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}

static void appendChildEvent(IOHIDEventRef parent, int type, int index, float x, float y)
{
    switch (type)
    {
        case TOUCH_MOVE:
			IOHIDEventAppendEvent(parent, generateChildEventTouchMove(index, x, y));
            break;
        case TOUCH_DOWN:
            IOHIDEventAppendEvent(parent, generateChildEventTouchDown(index, x, y));
            break;
        case TOUCH_UP:
            IOHIDEventAppendEvent(parent, generateChildEventTouchUp(index, x, y));
            break;
        default:
            NSLog(@"com.zjx.springboard: Unknown touch event type in appendChildEvent, type: %d", type);
    }
}

static void postIOHIDEvent(IOHIDEventRef event)
{
    static IOHIDEventSystemClientRef ioSystemClient = NULL;
    if (!ioSystemClient){
        ioSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    }
	if (senderID != 0)
    	IOHIDEventSetSenderID(event, senderID);
	else
	{		
		NSLog(@"### com.zjx.springboard: sender id is 0!");
		return;
	}
    IOHIDEventSystemClientDispatchEvent(ioSystemClient, event);
}

void performTouchFromRawData(UInt8 *eventData)
{
    // generate a parent event
	IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(), 3, 99, 1, 0, 0, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0, 0, 0); 
    IOHIDEventSetIntegerValue(parent , 0xb0019, 1); //set flags of parent event   flags: 0x20001 -> 0xa0001
    IOHIDEventSetIntegerValue(parent , 0x4, 1); //set flags of parent event   flags: 0xa0001 -> 0xa0011

    for (int i = 0; i < getTouchCountFromDataArray(eventData); i++)
    {
        //NSLog(@"### com.zjx.springboard: get data. index: %d. type: %d. touchIndex: %d. x: %f. y: %f", i, getTouchTypeFromDataArray(eventData, i), getTouchIndexFromDataArray(eventData, i), getTouchXFromDataArray(eventData, i), getTouchYFromDataArray(eventData, i));
        appendChildEvent(parent, getTouchTypeFromDataArray(eventData, i), getTouchIndexFromDataArray(eventData, i), getTouchXFromDataArray(eventData, i), getTouchYFromDataArray(eventData, i));
    }

    IOHIDEventSetIntegerValue(parent, 0xb0007, 0x23); // 设置parent的EventMask == 35
    IOHIDEventSetIntegerValue(parent, 0xb0008, 0x1); // parent flags: 0xa0011 -> 0xb0011
    IOHIDEventSetIntegerValue(parent, 0xb0009, 0x1); // 不知道设置哪里

    postIOHIDEvent(parent);
    CFRelease(parent);
}


//turns dataArray, which is 2 character representing a 2-digit integer into an int
static int getTaskType(UInt8* dataArray)
{
	//initializes taskType to 0
	int taskType = 0;
	//loops twice, each for each digit of the first 2 dataArray character
	for (int i = 0; i <= 1; i++)
	{
		//subtracts char 0 from current char because then every ASCII from 
		//0-9 will correspond to the ints 0 to 9
		//then for first digit it will multiply by 10^1, and second digit will 
		//multiply by 10^0, thus correctly each digit into it's integer position
		taskType += (dataArray[i] - '0')*pow(10, 1-i);
	}
	//return the integer in the first 2 character of dataArray but converted to an int
	return taskType;
}

void notifyClient(UInt8* msg, CFWriteStreamRef client)
{
	if (client != 0)
	{
		CFWriteStreamWrite(client, msg, strlen((char*)msg));
	}
}

//USED FOR DEBUGGING, COMMENT IT OUT WHEN NOT USING
void intToStr(int number, char *buffer, int bufferSize) {
    // Handle negative numbers
    if (number < 0) {
        *buffer++ = '-';
        number = -number;
    }

    // Convert the number to a string in reverse order
    int pos = 0;
    do {
        buffer[pos++] = '0' + (number % 10);
        number /= 10;
    } while (number > 0);

    // Add null-terminator
    buffer[pos] = '\0';

    // Reverse the string
    int start = 0;
    int e = pos - 1;
    while (start < e) {
        char temp = buffer[start];
        buffer[start] = buffer[e];
        buffer[e] = temp;
        start++;
        e--;
    }
}

void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    NSLog(@"### com.zjx.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
	/*go to usage in the readme for the format of buffer: https://github.com/xuan32546/IOS13-SimulateTouch/tree/58eb9474002ee5d22464e053fbeb73e4ed9ae751*/
	
	//the event data is everything after the first 2 digits of the buffer
    UInt8 *eventData = buff + 0x2;

	//gets the first 2 digits of buffer but as an int since it is a char right now
    int taskType = getTaskType(buff);

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        performTouchFromRawData(eventData);
		if (writeStreamRef)
			notifyClient((UInt8*)"0;;Touch\r\n", writeStreamRef);
    }
	else if (taskType == TASK_PRESS_HOME_BUTTON) { 
		IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0xC, 0x40, YES, 0);     
		postIOHIDEvent(event);   
		CFRelease(event);    
		event = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0xC, 0x40, NO, 0);    
		postIOHIDEvent(event);      
		CFRelease(event);
		if (writeStreamRef)
			notifyClient((UInt8*)"0;;Home button\r\n", writeStreamRef);
	}
	else if (taskType == TASK_PRESS_POWER_BUTTON) {   
		IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C, 0x30, 1, 0);    
		postIOHIDEvent(event);   
		CFRelease(event);    
		event = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C, 0x30, 0, 0);
		postIOHIDEvent(event);      
		CFRelease(event);
		if (writeStreamRef)
			notifyClient((UInt8*)"0;;Power button\r\n", writeStreamRef);
	}
	else if (taskType == TASK_USLEEP)
    {
        long int usleepTime = 0;
        //int usleepTime = 0;

        @try{
            //usleepTime = atoi((char*)eventData);
            usleepTime = strtol((char*)eventData, NULL, 10);
			//notifyClient((UInt8*)"just set time\r\n", writeStreamRef);
        }
        @catch (NSException *exception) {
            NSLog(@"com.zjx.springboard: Debug: %@", exception.reason);
            return;
        }
        //NSLog(@"com.zjx.springboard: sleep %d microseconds", usleepTime);
		//notifyClient((UInt8*)"about to sleep\r\n", writeStreamRef);
		// while (usleepTime > 0) {
		// 	notifyClient((UInt8*)"sleep for 5 more sec\r\n", writeStreamRef);
		// 	usleep(5000000);
		// 	usleepTime -= 5000000;
		// }
        const useconds_t maxMicroseconds = (useconds_t)-1; // Maximum value of useconds_t
        
        while (usleepTime > 0) {
            char buffer[20];
            useconds_t chunk = usleepTime > maxMicroseconds ? maxMicroseconds : (useconds_t)usleepTime;
            snprintf(buffer, sizeof(buffer), "%u", chunk);
            //intToStr(number, buffer, sizeof(buffer));
            notifyClient((UInt8*)buffer, writeStreamRef);
            usleep(chunk);
            usleepTime -= chunk;
        }
        //usleep(usleepTime);

		if (writeStreamRef)
			notifyClient((UInt8*)"0;;Sleep ends\r\n", writeStreamRef);
		//showAlertBox(@"Alert Works", [NSString stringWithFormat:@"%d", usleepTime], 999);
    }
    else if (taskType == TASK_TAKE_SCREENSHOT) {
        UIImage *screenImage = _UICreateScreenUIImage();
        NSData *imgData = UIImagePNGRepresentation(screenImage);
        UInt8 *dataBuffer = (UInt8 *)[imgData bytes];
        //[UIImagePNGRepresentation(screenImage) writeToFile:@"/var/mobile/test_pic.png" atomically:NO];
        
        UInt32 byteCount = (UInt32)[imgData length];
        UInt32 networkByteCount = (UInt32)htonl(byteCount);
        UInt8 *byteCountPtr = (UInt8 *)&networkByteCount;
        //sends over length of data as a prefix of 4 bytes
        if (writeStreamRef)
            CFWriteStreamWrite(writeStreamRef, byteCountPtr, 4);
        //sends over image
        if (writeStreamRef) {
            CFIndex totalBytesWritten = 0;
            CFIndex bytesWritten = 0;
            while (totalBytesWritten < byteCount) {
                bytesWritten = CFWriteStreamWrite(writeStreamRef, dataBuffer + totalBytesWritten, byteCount - totalBytesWritten);
                if (bytesWritten > 0) {
                    totalBytesWritten += bytesWritten;
                } else {
                    // Handle error or write operation failure
                    break;
                }
            }
        }
            //CFWriteStreamWrite(writeStreamRef, dataBuffer, (CFIndex)byteCount);


    }
    // else if (taskType == TASK_PROCESS_BRING_FOREGROUND) //bring to foreground
    // {
    //     switchProcessForegroundFromRawData(eventData);
    // }
    // else if (taskType == TASK_SHOW_ALERT_BOX)
    // {
    //     showAlertBoxFromRawData(eventData);
    // }
    // else if (taskType == TASK_RUN_SHELL)
    // {
    //     system([[NSString stringWithFormat:@"sudo zxtouchb -e \"%s\"", eventData] UTF8String]);
    // }
    // else if (taskType == TASK_TOUCH_RECORDING_START)
    // {
    //     startRecording();    
        
    //     /*
    //     FILE *file = fopen("/var/mobile/Documents/com.zjx.zxtouchsp/recording/201210140654.bdl/201210140654.raw", "r");
    
    //     char buffer[256];
    //     int taskType;
    //     int sleepTime;
        
    //     while (fgets(buffer, sizeof(char)*256, file) != NULL){
    //         processTask((UInt8 *)buffer);
    //         //NSLog(@"%s",buffer);
    //     }
    //     */
        
    // }
    // else if (taskType == TASK_TOUCH_RECORDING_STOP)
    // {
    //     stopRecording();    
    // }
    // else if (taskType == TASK_PLAY_SCRIPT)
    // {
    //     playScript(eventData);
    // }
    // else if (taskType == TASK_PLAY_SCRIPT_FORCE_STOP)
    // {
    //     playForceStop();
    // }
}

static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo) 
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UInt8 readDataBuff[2048];
		
		memset(readDataBuff, 0, sizeof(readDataBuff));
		
		CFIndex hasRead = CFReadStreamRead(readStream, readDataBuff, sizeof(readDataBuff));
		

		if (hasRead > 0) {

			//don't know how it works, copied from https://www.educative.io/edpresso/splitting-a-string-using-strtok-in-c
			
			for(char * charSep = strtok((char*)readDataBuff, "\n\r"); charSep != NULL; charSep = strtok(NULL, "\n\r")) {
				UInt8 *buff = (UInt8*)charSep;
				id temp = [socketClients objectForKey:@((long)readStream)];
				if (temp != nil)
					processTask(buff, (CFWriteStreamRef)[temp longValue]);
				else
					processTask(buff, nil);
				//NSLog(@"com.zjx.springboard: get data: %s", buff);
			}
			//向客户端输出数据
			//NSLog(@"com.zjx.springboard: return value: %d, ref: %d", CFWriteStreamWrite(writeStreamRef, (UInt8 *)"str", 3), writeStreamRef);

			//countsss++;
		}
	});
}

// int notifyClient(UInt8* msg)
// {
//     return CFWriteStreamWrite(writeStreamRef, msg, strlen((char*)msg));
// }

static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    if (kCFSocketAcceptCallBack == type) {
        
        CFSocketNativeHandle  nativeSocketHandle = *(CFSocketNativeHandle *)data;
        
        uint8_t name[SOCK_MAXADDRLEN];
        socklen_t namelen = sizeof(name);
        

        if (getpeername(nativeSocketHandle, (struct sockaddr *)name, &namelen) != 0) {
            
            NSLog(@"### com.zjx.springboard: ++++++++getpeername+++++++");
            
            exit(1);
        }
        
        //struct sockaddr_in *addr_in = (struct sockaddr_in *)name;
        
        //NSLog(@"### com.zjx.springboard: connection starts", inet_ntoa(addr_in-> sin_addr), addr_in->sin_port);
        
        readStreamRef = NULL;
        writeStreamRef = NULL;
        
        
		
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStreamRef, &writeStreamRef);
       
        if (readStreamRef && writeStreamRef) {
            CFReadStreamOpen(readStreamRef);
            CFWriteStreamOpen(writeStreamRef);
            
            CFStreamClientContext context = {0, NULL, NULL, NULL };
            
            
    
            if (!CFReadStreamSetClient(readStreamRef, kCFStreamEventHasBytesAvailable, readStream, &context)) {
                NSLog(@"### com.zjx.springboard: error 1");
                return;
            }
            
            CFReadStreamScheduleWithRunLoop(readStreamRef, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
			
			[socketClients setObject:@((long)writeStreamRef) forKey:@((long)readStreamRef)];
            
           
			
        }
        else
        {
            close(nativeSocketHandle);
        }
		
    }
    
}

void socketServer()
{
    @autoreleasepool {
        CFSocketRef _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, TCPServerAcceptCallBack, NULL);
        
        if (_socket == NULL) {
            NSLog(@"### com.zjx.springboard: failed to create socket.");
            return;
        }
        
        UInt32 reused = 1;
        
        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, (const void *)&reused, sizeof(reused));
        
        struct sockaddr_in Socketaddr;
        memset(&Socketaddr, 0, sizeof(Socketaddr));
        Socketaddr.sin_len = sizeof(Socketaddr);
        Socketaddr.sin_family = AF_INET;
        
        Socketaddr.sin_addr.s_addr = inet_addr(ADDR);
        Socketaddr.sin_port = htons(PORT);
        
        CFDataRef address = CFDataCreate(kCFAllocatorDefault,  (UInt8 *)&Socketaddr, sizeof(Socketaddr));
        
        if (CFSocketSetAddress(_socket, address) != kCFSocketSuccess) {
            
            if (_socket) {
                CFRelease(_socket);
                //exit(1);
            }
            
            _socket = NULL;
        }
        
		socketClients = [[NSMutableDictionary alloc] init];

        NSLog(@"### com.zjx.springboard: connection waiting");
        CFRunLoopRef cfrunLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);

        CFRunLoopAddSource(cfrunLoop, source, kCFRunLoopCommonModes);

        CFRelease(source);
        CFRunLoopRun();
    }

}

//I think this is to take care of if the screen is rotated
void setScreenSize(CGFloat x, CGFloat y)
{
    extern CGFloat device_screen_width;
    extern CGFloat device_screen_height;
	device_screen_width = x;
	device_screen_height = y;

	if (device_screen_width == 0 || device_screen_height == 0 || device_screen_width > 10000 || device_screen_height > 10000)
	{
		NSLog(@"### com.zjx.springboard: Unable to initialze the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
	else
	{
		NSLog(@"### com.zjx.springboard: successfully initialize the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
} 

%ctor{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		//I believe this sets up the device to be able to receive touch commands
		startSetSenderIDCallBack();
		//This opens a socket, then listens for commands to be sent
		socketServer();
	});
}

%hook SpringBoard
#define CGRectSetPos( r, x, y ) CGRectMake( x, y, r.size.width, r.size.height )

- (void)applicationDidFinishLaunching:(id)arg1
{
    %orig;
    CGFloat screen_scale = [[UIScreen mainScreen] scale];

    CGFloat width = [UIScreen mainScreen].bounds.size.width * screen_scale;
    CGFloat height = [UIScreen mainScreen].bounds.size.height * screen_scale;

    setScreenSize(width<height?width:height, width>height?width:height);


    NSLog(@"com.zjx.springboard: width: %f, height: %f", width, height);
}
%end
