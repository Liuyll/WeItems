//
//  EditItemView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    @State var item: Item
    @State private var selectedType: ItemType
    @State private var showingAddGroup = false
    @State private var selectedPhoto: PhotosPickerItem?
    
    init(item: Item, store: ItemStore, groupStore: GroupStore) {
        self._item = State(initialValue: item)
        self.store = store
        self.groupStore = groupStore
        // 根据 item.type 初始化 selectedType
        self._selectedType = State(initialValue: ItemType(rawValue: item.type) ?? .other)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section("基本信息") {
                    TextField("物品名称", text: $item.name)
                    
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("价格", value: $item.price, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("类型", selection: $selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .onChange(of: selectedType) { _, newValue in
                        item.type = newValue.rawValue
                    }
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
                        Picker("选择分组", selection: $item.groupId) {
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
                        if let imageData = item.imageData,
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
                        
                        PhotosPicker(selection: $selectedPhoto,
                                   matching: .images) {
                            Label(item.imageData == nil ? "选择照片" : "更换照片",
                                  systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    item.imageData = data
                                }
                            }
                        }
                        
                        if item.imageData != nil {
                            Button(role: .destructive) {
                                item.imageData = nil
                                selectedPhoto = nil
                            } label: {
                                Label("删除图片", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 详情
                Section("详情描述") {
                    TextEditor(text: $item.details)
                        .frame(minHeight: 80)
                }
                
                // 购买链接
                Section("购买链接") {
                    TextField("输入链接地址", text: $item.purchaseLink)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("编辑物品")
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
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
        }
    }
    
    private func saveItem() {
        store.update(item)
        dismiss()
    }
}

#Preview {
    EditItemView(
        item: Item(name: "测试物品", details: "详情", purchaseLink: "", price: 100, type: "其他"),
        store: ItemStore(),
        groupStore: GroupStore()
    )
}
