import socket
import time

# touch event types
TOUCH_UP = 0
TOUCH_DOWN = 1
TOUCH_MOVE = 2


def getSocketToDevice(ip_address, port):
	s = socket.socket()
	s.connect((ip_address, port))  
	return s
	
# you can copy and paste these methods to your code
def formatSocketData(type, index, x, y):
	return '{}{:02d}{:05d}{:05d}'.format(type, index, int(x*10), int(y*10))

def touch(s, type, finger_index, x, y):
	if int(finger_index) > 19:
		print("Touch index should not be greater than 19.")
	s.send(("101" + formatSocketData(type, finger_index, x, y) + "\n\r").encode())
	s.recv(1024)

def press_home_button(s):
	s.send("29\n\r".encode())
	s.recv(1024)

def press_power_button(s):
	s.send("30\n\r".encode())
	s.recv(1024)

def accurate_usleep(s, us):
	s.send((f"18{us}\n\r").encode())
	while True:
		tmp = s.recv(1024).decode()
		print(tmp)
		if '0;;' in tmp:
			break

def take_screenshot(s):
	s.send("31\n\r".encode())
	dataSizeBytes = s.recv(4)
	remaining_bytes = int.from_bytes(dataSizeBytes, byteorder='big', signed=False)
	screenshot_data = b""
	s.settimeout(5)
	try:
		while remaining_bytes > 0:
			data_chunk = s.recv(min(4096, remaining_bytes))
			screenshot_data += data_chunk
			remaining_bytes -= len(data_chunk)
			print(remaining_bytes)
	finally:
		s.settimeout(None)
	return screenshot_data

def press(s, x, y):
	touch(s, TOUCH_DOWN, 1, x, y) 
	time.sleep(0.1)
	touch(s, TOUCH_UP, 1, x, y)

def close_n_apps(s, n):
	press_home_button(s)
	time.sleep(2)
	press_home_button(s)
	time.sleep(0.1)
	press_home_button(s)
	time.sleep(1)

	#fixes touch glitch that occurs when closing apps right after unlocking phone
	press(s,0,0)
	time.sleep(1)
	press(s,0,0)
	time.sleep(1)
	press_home_button(s)
	time.sleep(0.1)
	press_home_button(s)
	time.sleep(1)
	touch(s, TOUCH_DOWN, 1, 400, 1000)
	time.sleep(0.1)
	touch(s, TOUCH_MOVE, 1, 400, 1400)
	time.sleep(0.1)
	touch(s, TOUCH_UP, 1, 400, 1400)
	time.sleep(1)

	for _ in range(n):
		touch(s, TOUCH_DOWN, 1, 400, 1000)
		time.sleep(0.1)
		touch(s, TOUCH_MOVE, 1, 400, 0)
		time.sleep(0.1)
		touch(s, TOUCH_UP, 1, 400, 0)
		time.sleep(1)
	press_home_button(s)

def unlock_phone(s):
	press_power_button(s)
	time.sleep(1)

	#touch top of screen to reset touch after powering on glitch
	press(s, 370, 100)
	time.sleep(1)

	press_home_button(s)
	time.sleep(1.5)

	#do it again because more glitches
	press(s, 370, 100)
	time.sleep(1)

	#type password
	#PUT PRESSES FOR YOUR PASSWORD HERE

	press_home_button(s) #make sure it is in first page
	time.sleep(1)

	#press cancel on top right if search menu opens 
	press(s, 685, 70)
	time.sleep(0.5)
	press(s, 685, 70)
	time.sleep(1)

	press_home_button(s) #make sure it is in first page again (in case it was in app before)
	time.sleep(1)

	press(s, 460, 1000) #press empty spot to fix any touch glitches
	time.sleep(1)

