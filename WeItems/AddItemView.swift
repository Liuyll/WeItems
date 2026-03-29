//
//  AddItemView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    var defaultGroupId: UUID?
    
    @State private var name = ""
    @State private var details = ""
    @State private var price = ""
    @State private var selectedType: ItemType = .other
    @State private var selectedGroupId: UUID?
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var compressedImageData: Data?
    
    @State private var showingAddGroup = false
    @State private var showingCelebration = false
    @State private var showingDuplicateAlert = false
    @State private var spiritTravelCount = 0
    @State private var isLargeItem = false
    
    private var isValid: Bool {
        !name.isEmpty && !price.isEmpty && Double(price) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section("基本信息") {
                    TextField("物品名称", text: $name)
                    
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("价格", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("类型", selection: $selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    
                    Toggle("大件", isOn: $isLargeItem)
                }
                
                // 分组选择
                Section("所属分组") {
                    if groupStore.groups.isEmpty {
                        Button {
                            showingAddGroup = true
                        } label: {
                            Label("创建分组", systemImage: "folder.badge.plus")
                        }
                    } else {
                        Picker("选择分组", selection: $selectedGroupId) {
                            Text("无分组")
                                .tag(nil as UUID?)
                            
                            ForEach(groupStore.groups) { group in
                                Label(group.name, systemImage: group.icon)
                                    .tag(group.id as UUID?)
                            }
                        }
                        
                        Button {
                            showingAddGroup = true
                        } label: {
                            Label("新建分组", systemImage: "folder.badge.plus")
                        }
                    }
                }
                
                // 图片选择
                Section("图片") {
                    VStack(spacing: 16) {
                        if let imageData = selectedImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.gray)
                                        Text("选择图片")
                                            .foregroundStyle(.secondary)
                                    }
                                )
                        }
                        
                        HStack {
                            PhotosPicker(selection: $selectedPhoto,
                                       matching: .images) {
                                Label(selectedImageData == nil ? "选择照片" : "更换照片",
                                      systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .onChange(of: selectedPhoto) { _, newValue in
                                Task {
                                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                        selectedImageData = data
                                        // 生成 0.7 压缩版，仅用于同步上传
                                        if let uiImage = UIImage(data: data) {
                                            compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                        }
                                    }
                                }
                            }
                            
                            if selectedImageData != nil {
                                Divider()
                                Button(role: .destructive) {
                                    selectedImageData = nil
                                    compressedImageData = nil
                                    selectedPhoto = nil
                                } label: {
                                    Label("删除图片", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 详情
                Section("详情描述") {
                    TextEditor(text: $details)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("添加物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
            .fullScreenCover(isPresented: $showingCelebration, onDismiss: {
                dismiss()
            }) {
                SpiritTravelCelebrationView(count: spiritTravelCount)
            }
            .alert("同名物品已存在", isPresented: $showingDuplicateAlert) {
                Button("确定") {}
            } message: {
                Text("已存在名为「\(name)」的物品，请更换名称后重试。")
            }
            .onAppear {
                selectedGroupId = defaultGroupId
            }
        }
    }
    
    private func saveItem() {
        guard let priceValue = Double(price) else { return }
        
        // 检查是否存在同名物品
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.items.contains(where: { $0.name == trimmedName }) {
            showingDuplicateAlert = true
            return
        }
        
        let newItem = Item(
            name: name,
            details: details,
            purchaseLink: "",
            imageData: selectedImageData,
            compressedImageData: compressedImageData,
            imageChanged: selectedImageData != nil,
            price: priceValue,
            type: selectedType.rawValue,
            groupId: selectedGroupId,
            isLargeItem: isLargeItem
        )
        
        store.add(newItem)
        
        // 检查是否为精神旅行类型
        if selectedType == .outdoor {
            // 统计本年度精神旅行次数（包括刚添加的）
            spiritTravelCount = countCurrentYearSpiritTravels()
            showingCelebration = true
        } else {
            dismiss()
        }
    }
    
    private func countCurrentYearSpiritTravels() -> Int {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        return store.items.filter { item in
            let itemYear = calendar.component(.year, from: item.createdAt)
            // 统计本年度所有精神旅行物品（包括已归档的，不包括已删除的）
            return item.type == ItemType.outdoor.rawValue && 
                   itemYear == currentYear &&
                   item.listType == .items
        }.count
    }
}

#Preview {
    AddItemView(store: ItemStore(), groupStore: GroupStore())
}
