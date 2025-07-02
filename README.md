بالتأكيد، لقد قمت بإعادة ترتيب وتنظيم الدليل ليكون دليلاً متكاملاً ومرتباً خطوة بخطوة لشخص يقوم بتشغيل بيئة كافكا هذه لأول مرة على جهازه.

-----

## 📜 دليل التشغيل خطوة بخطوة لإعداد Kafka لأول مرة

مرحباً بك\! هذا الدليل سيأخذك في رحلة إعداد وتشغيل كلاستر كافكا مؤمَّن بالكامل باستخدام نمط KRaft (بدون ZooKeeper). جميع ملفات الإعداد والسكربتات اللازمة موجودة وجاهزة. اتبع الخطوات التالية بالترتيب.
لازم تنقل مجلد kafka الي /opt/kafka من اجل تفادي الاخطاء
### **الخطوة 1: توليد شهادات الأمان (SSL Certificates)** 🛡️

هذه هي الخطوة الأولى والأساسية لتأمين جميع الاتصالات داخل الكلاستر ومع العملاء.

1.  افتح نافذة الأوامر (Terminal).
2.  انتقل إلى مجلد الإعدادات:
    ```bash
    cd /opt/kafka/config/kraft
    ```
3.  قم بتشغيل سكربت توليد الشهادات:
    ```bash
    ./certfcat.sh
    ```
    سيقوم هذا السكربت بإنشاء مجلد `ssl/` جديد يحتوي على جميع الشهادات والمفاتيح اللازمة للخوادم والعملاء.

-----

### **الخطوة 2: تهيئة الكلاستر لأول مرة (One-Time Setup)** ⚙️

هذه العملية تُنفذ مرة واحدة فقط عند إنشاء الكلاستر لتهيئة مساحات التخزين الخاصة بـ KRaft.

1.  **توليد معرّف فريد للكلاستر (Cluster ID):**

    ```bash
    CLUSTER_ID=$(bin/kafka-storage.sh random-uuid)
    echo "Cluster ID: $CLUSTER_ID"
    ```

    احتفظ بهذا المعرّف، ستحتاجه في النقطة التالية.

2.  **تهيئة مجلدات التخزين (Format Storage):**
    استخدم المعرّف الذي أنشأته لتهيئة كل خادم في الكلاستر.

    ```bash
    # تهيئة الخادم الأول
    bin/kafka-storage.sh format -t $CLUSTER_ID -c config/kraft/server-0.properties

    # تهيئة الخادم الثاني
    bin/kafka-storage.sh format -t $CLUSTER_ID -c config/kraft/server-1.properties

    # تهيئة الخادم الثالث
    bin/kafka-storage.sh format -t $CLUSTER_ID -c config/kraft/server-2.properties
    ```

-----

### **الخطوة 3: تشغيل خوادم كافكا (Start Kafka Servers)** 🚀

أنت الآن جاهز لبدء تشغيل الكلاستر.

1.  **تصدير متغير البيئة الخاص بالمصادقة (JAAS):** هذا المتغير يخبر كافكا بمكان ملف أسماء المستخدمين وكلمات المرور.
    ```bash
    export KAFKA_OPTS="-Djava.security.auth.login.config=config/kraft/kafka_server_jaas.conf"
    ```
2.  **تشغيل الخوادم:** لديك طريقتان:
      * **الطريقة السهلة (موصى بها):** باستخدام سكربت الإدارة المرفق.
        ```bash
        bin/kafka-manager start
        ```
      * **الطريقة اليدوية:**
        ```bash
        bin/kafka-server-start.sh -daemon config/kraft/server-0.properties
        bin/kafka-server-start.sh -daemon config/kraft/server-1.properties
        bin/kafka-server-start.sh -daemon config/kraft/server-2.properties
        ```
    **نصيحة:** يمكنك استخدام الأمر `bin/kafka-manager status` للتأكد من أن جميع الخوادم تعمل بنجاح.

-----

### **الخطوة 4: إنشاء موضوع وتعيين الصلاحيات (Topics & ACLs)** 🔐

الآن بعد أن أصبح الكلاستر يعمل، سنقوم بإنشاء موضوع (Topic) وتحديد من يمكنه استخدامه. سنستخدم حساب **المدير (`admin`)** للقيام بهذه المهام الإدارية.

1.  **إنشاء موضوع جديد:**

    ```bash
    bin/kafka-topics.sh --create --topic secure-topic --partitions 1 --replication-factor 2 --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

2.  **منح صلاحيات الوصول للمستخدم `user2_bajash`:**
    سنمنح هذا المستخدم صلاحية الكتابة (`WRITE`) والقراءة (`READ`) على الموضوع الذي أنشأناه.

    ```bash
    bin/kafka-acls.sh --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties --add --allow-principal User:user2_bajash --operation WRITE --operation READ --topic secure-topic
    ```

-----

### **الخطوة 5: اختبار الإنتاج والاستهلاك (Test the Setup)** ✅

هذه هي لحظة الحقيقة\! سنتحقق من أن المستخدم `user2_bajash` يمكنه إرسال واستقبال الرسائل باستخدام الصلاحيات التي مُنحت له.

1.  **إرسال الرسائل (Producer):**
    افتح نافذة أوامر جديدة وقم بتشغيل الأمر التالي. سيسمح لك بكتابة رسائل مباشرة من سطر الأوامر.

    ```bash
    # استخدم ملف إعدادات العميل العادي client-ssl.properties
    bin/kafka-console-producer.sh --broker-list 192.168.168.44:9094 --topic secure-topic --producer.config config/kraft/client-ssl.properties
    ```

    اكتب بعض الرسائل مثل "Hello Kafka" واضغط Enter. اضغط `Ctrl+C` للخروج عند الانتهاء.

2.  **استقبال الرسائل (Consumer):**
    افتح نافذة أوامر **ثالثة** وقم بتشغيل أمر المستهلك.

    ```bash
    # استخدم نفس ملف إعدادات العميل
    bin/kafka-console-consumer.sh --bootstrap-server 192.168.168.44:9094 --topic secure-topic --from-beginning --consumer.config config/kraft/client-ssl.properties
    ```

    إذا ظهرت الرسائل التي أرسلتها في نافذة المستهلك، فهذا يعني أن الكلاستر يعمل بشكل مثالي مع نظام الأمان والصلاحيات. **تهانينا\!** 🎉

-----

### **أوامر إضافية للإدارة**
**ملاحظة هامة:** جميع الأوامر التالية هي أوامر إدارية، لذا يجب تنفيذها باستخدام ملف صلاحيات المدير (`admin-sasl-ssl.properties`).
  * **لإيقاف جميع الخوادم:**
    ```bash
    bin/kafka-manager stop
    ```
  * **لعرض جميع المواضيع:**
    ```bash
    bin/kafka-topics.sh --list --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```
  * **لعرض الصلاحيات على موضوع معين:**
    ```bash
    bin/kafka-acls.sh --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties --list --topic secure-topic
    ```


   



-----

### 🗂️ **إدارة المواضيع (Topic Management)**

هذه هي المهام الأكثر شيوعًا التي ستقوم بها.

  * **وصف موضوع (Describe a Topic):**

      * لمعرفة تفاصيل موضوع معين، مثل عدد الأقسام، ومن هو القائد (Leader) لكل قسم، والنسخ المتزامنة (ISR). هذا الأمر حيوي لتشخيص المشاكل.

    <!-- end list -->

    ```bash
    bin/kafka-topics.sh --describe --topic secure-topic --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

      * **ماذا تبحث عنه؟** تأكد من أن عدد النسخ في `Replicas` يساوي عدد النسخ في `Isr`. إذا كانا غير متساويين، فهذا يعني أن أحد البروكرات غير متزامن.

  * **تعديل موضوع (Alter a Topic):**

      * لزيادة عدد الأقسام (Partitions) لموضوع موجود. لا يمكنك تقليل عدد الأقسام.

    <!-- end list -->

    ```bash
    # زيادة عدد أقسام الموضوع secure-topic إلى 3
    bin/kafka-topics.sh --alter --topic secure-topic --partitions 3 --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

  * **حذف موضوع (Delete a Topic):**

      * **تحذير:** هذا الإجراء يحذف الموضوع وجميع بياناته بشكل دائم.

    <!-- end list -->

    ```bash
    bin/kafka-topics.sh --delete --topic secure-topic --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

      * **شرط:** يجب أن تكون قيمة `delete.topic.enable=true` مفعلة في إعدادات البروكرات (وهي القيمة الافتراضية).

-----

### 🔐 **إدارة صلاحيات الوصول (ACL Management)**

  * **إزالة صلاحية (Remove an ACL):**
      * لإلغاء صلاحية معينة من مستخدم.
    <!-- end list -->
    ```bash
    # إزالة صلاحية الكتابة WRITE من المستخدم user2_bajash على الموضوع secure-topic
    bin/kafka-acls.sh --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties --remove --allow-principal User:user2_bajash --operation WRITE --topic secure-topic
    ```

-----

### 👥 **إدارة مجموعات المستهلكين (Consumer Group Management)**

هذه الأوامر ضرورية لمراقبة أداء تطبيقات المستهلكين.

  * **عرض جميع مجموعات المستهلكين (List Consumer Groups):**

    ```bash
    bin/kafka-consumer-groups.sh --list --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

  * **وصف مجموعة مستهلكين (Describe a Consumer Group):**

      * **الأمر الأهم لمراقبة المستهلكين.** يعرض لك حالة كل قسم يقرأ منه المستهلك، وأهم معلومة هي **التأخير (LAG)**.

    <!-- end list -->

    ```bash
    bin/kafka-consumer-groups.sh --describe --group my-consumer-group --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

      * **ماذا تبحث عنه؟** انظر إلى عمود **`LAG`**. إذا كانت قيمته صفرًا أو قريبة من الصفر، فهذا يعني أن المستهلك يواكب المنتج. إذا كانت القيمة كبيرة أو تزداد باستمرار، فهذا يدل على وجود مشكلة في تطبيق المستهلك (بطيء جدًا أو متوقف).

-----

### ❤️‍🩹 **مراقبة صحة الكلاستر (Cluster Health)**

  * **وصف الكلاستر (Describe the Cluster):**

      * للحصول على نظرة عامة على الكلاستر، بما في ذلك البروكرات النشطة ومعرّف الكنترولر القائد.

    <!-- end list -->

    ```bash
    bin/kafka-cluster.sh describe --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties
    ```

  * **فحص كواروم الكنترولر (Check KRaft Quorum):**

      * هذا الأمر خاص بوضع KRaft، وهو مهم جدًا لتشخيص مشاكل الكنترولر.

    <!-- end list -->

    ```bash
    bin/kafka-metadata-quorum.sh --bootstrap-server 192.168.168.44:9094 --command-config config/kraft/admin-sasl-ssl.properties describe --status
    ```

      * **ماذا تبحث عنه؟** تأكد من وجود قائد (`Leader`) واحد وأن جميع العقد الأخرى تظهر كـ `Follower`.
