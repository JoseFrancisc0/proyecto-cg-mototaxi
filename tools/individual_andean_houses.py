"""Named individual references in Cusco, from Reactivo's project photographs."""
def andean_individual(v,w,d):
    global wall,house_width
    house_width=w
    whitewall=material('Cal contemporanea andina',color=rgb('d2cfc3'));bind_surface_normal(whitewall,materials['sierra'][8],.22)
    dark=material('Enchape gris oscuro andino',color=rgb('474a48'));bind_surface_normal(dark,materials['costa'][10],.25)
    frame=material('Aluminio andino negro',color=rgb('232a2b'),metal=.35)
    timber=honey_wood;stone=materials['sierra'][5];wall=whitewall;base=.16;front=-d*.5
    if v==0:
        # Kinsawasi: timber left wing, white upper room, stone chimney and a
        # shallow clay-tile awning; the tall right slit belongs to its own bay.
        box('Cuerpo de vivienda Kinsawasi',(0,0,3.15),(w,d,6.0),whitewall)
        box('Ala de madera',(-w*.31,-.08,2.7),(w*.38,d+.16,5.1),timber)
        door(-w*.27,front-.11,base,timber,w=1.18,h=2.50,kind=4,glass_override=reference_dark_glass)
        window(-w*.28,front-.14,4.25,w*.27,1.65,False,frame,4,reference_dark_glass)
        window(w*.18,front-.04,4.85,w*.48,2.05,False,frame,4,reference_dark_glass)
        window(w*.40,front-.07,1.65,.72,2.60,False,frame,0,reference_dark_glass)
        box('Chimenea y pantalla de piedra',(w*.25,front-.23,1.65),(.80,.36,2.95),stone)
        awning=box('Alero de teja',(w*.10,front-.63,3.21),(w*.75,1.25,.13),materials['sierra'][10]);awning.rotation_euler.x=.10
        roof=box('Techo inclinado principal',(w*.12,.02,6.28),(w*.80,d+.60,.18),materials['sierra'][10]);roof.rotation_euler.y=.045
        for j in range(9):pole('Canecillo visto',(-w*.25+j*w*.083,front-.15,6.12),(-w*.25+j*w*.083,front-.44,6.12),.035,timber)
        roof=box('Cubierta de ala de madera',(-w*.31,0,5.31),(w*.42,d+.40,.18),timber);roof.rotation_euler.y=-.07
    elif v==1:
        # Larapa: asymmetric white frames and a stone corner over a dark base.
        box('Planta baja oscura',(0,0,1.61),(w,d,2.90),dark)
        box('Planta alta blanca',(0,0,4.64),(w,d,3.16),whitewall)
        door(-w*.08,front-.11,base,timber,w=1.12,h=2.5,kind=1)
        window(-w*.33,front-.04,2.90,w*.18,5.0,False,frame,4,reference_curtain)
        window(w*.26,front-.04,1.50,w*.32,1.80,False,frame,0,reference_curtain)
        window(w*.39,front-.04,4.65,w*.12,2.0,False,frame,0,reference_curtain)
        box('Esquina de piedra',(w*.17,front-.20,4.65),(w*.25,.32,3.0),stone)
        box('Marco superior',(0,front-.25,6.32),(w+.16,.65,.24),whitewall)
        for x in [-w*.47,w*.47]:box('Retorno de marco',(x,front-.25,4.70),(.24,.65,3.30),whitewall)
        box('Cubierta plana',(0,0,6.40),(w+.12,d+.12,.18),whitewall)
    elif v==2:
        # Zarumilla: five vertical opening axes and recessed Juliet rails.
        level=2.9;floors=6
        box('Edificio Zarumilla',(0,0,base+level*floors*.5),(w,d,level*floors),whitewall)
        garage(-w*.29,front-.12,base,w*.30,2.55,False)
        door(w*.19,front-.10,base,frame,w=1.25,h=2.55,kind=4,glass_override=reference_dark_glass)
        for f in range(1,floors):
            for j in range(5):
                x=(j-2)*w*.188;z=base+f*level
                window(x,front-.03,z+1.39,w*.115,2.05,False,frame,4,reference_curtain)
                bars=[((x-w*.06,front-.24,z+.30),(x+w*.06,front-.24,z+.30),.015),((x-w*.06,front-.24,z+1.05),(x+w*.06,front-.24,z+1.05),.015)]
                for k in range(8):
                    xx=x-w*.06+k*w*.12/7;bars.append(((xx,front-.24,z+.30),(xx,front-.24,z+1.05),.010))
                rail_segments('Reja de antepecho',bars,frame)
            rear_windows(w,d,base+f*level+1.4,frame,4)
        box('Alero corrido',(0,0,base+floors*level+.15),(w+.55,d+.55,.20),materials['sierra'][10])
    else:
        # Enaco: complete loggias with side returns and dark central portals.
        level=3.0;floors=8
        box('Planta de acceso',(0,0,1.60),(w,d,2.90),dark)
        door(0,front-.11,base,frame,w=1.45,h=2.55,kind=4,glass_override=reference_dark_glass)
        garage(-w*.31,front-.12,base,w*.25,2.55,False)
        for f in range(1,floors):
            z=base+f*level
            box('Habitaciones retranqueadas',(0,.7,z+1.45),(w,d-1.4,2.90),whitewall)
            for j in range(3):
                x=(j-1)*w*.31
                window(x,front+1.35,z+1.40,w*.25,2.35,False,frame,4,reference_curtain)
                loggia(x,front+.57,z+.04,w*.29,1.62,whitewall,reference_dark_glass)
                if j!=1:
                    box('Pantalla de madera',(x+(-1 if (f+j)%2 else 1)*w*.105,front+.15,z+1.44),(w*.075,.26,2.90),timber)
                else:
                    box('Antepecho central oscuro',(x,front-.25,z+.55),(w*.29,.20,1.05),dark)
                    for sign in [-1,1]:box('Retorno de portal central',(x+sign*w*.145,front+.37,z+1.45),(.15,1.45,2.90),dark)
                    box('Dintel oscuro',(x,front+.38,z+2.88),(w*.30,1.45,.20),dark)
            rear_windows(w,d,z+1.45,frame,3)
        for sign in [-1,1]:box('Marco continuo de fachada',(sign*w*.49,front+.35,base+floors*level*.5),(.20,1.6,floors*level),whitewall)
        box('Cubierta del edificio',(0,0,base+floors*level+.06),(w+.2,d+.2,.18),whitewall)
    if v<2:rear_windows(w,d,4.65,frame,3)
    rear_windows(w,d,1.65,frame,3)
    for sign in [-1,1]:
        for y in [-d*.18,d*.27]:side_opening(sign,y,1.6,1.10,1.4,frame)
